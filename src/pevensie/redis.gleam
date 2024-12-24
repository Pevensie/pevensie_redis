import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import mug
import pevensie/cache
import pevensie/drivers
import radish
import radish/error as radish_error

type Radish =
  Subject(radish.Message)

pub type Redis {
  Redis(config: RedisConfig, conn: Option(Radish))
}

pub type RedisError {
  StartError(actor.StartError)
  ActorError
  ConnectionError
  TCPError(mug.Error)
  ServerError(String)
  UnknownResponseError
}

fn radish_error_to_redis_error(err: radish_error.Error) -> RedisError {
  case err {
    radish_error.ActorError -> ActorError
    radish_error.ConnectionError -> ConnectionError
    radish_error.TCPError(err) -> TCPError(err)
    radish_error.ServerError(err) -> ServerError(err)
    radish_error.RESPError -> UnknownResponseError
    // We should never reach this as NotFound errors should be handled and
    // converted to `cache.GetError(_)`s
    radish_error.NotFound -> panic as "NotFoundError should be handled"
  }
}

pub type RedisConfig {
  RedisConfig(
    host: String,
    port: Int,
    timeout: Int,
    username: Option(String),
    password: Option(String),
  )
}

pub fn default_config() -> RedisConfig {
  RedisConfig(
    host: "localhost",
    port: 6379,
    timeout: 5000,
    username: None,
    password: None,
  )
}

@internal
pub fn redis_config_to_radish_start_options(
  config: RedisConfig,
) -> List(radish.StartOption) {
  let options = [radish.Timeout(config.timeout)]
  let options = case config {
    RedisConfig(username: Some(username), password: Some(password), ..) -> [
      radish.AuthWithUsername(username, password),
      ..options
    ]
    RedisConfig(username: Some(username), password: None, ..) -> [
      radish.AuthWithUsername(username, ""),
      ..options
    ]
    RedisConfig(username: None, password: Some(password), ..) -> [
      radish.Auth(password),
      ..options
    ]
    _ -> options
  }
  options
}

pub fn new_cache_driver(
  config: RedisConfig,
) -> cache.CacheDriver(Redis, RedisError) {
  cache.CacheDriver(
    driver: Redis(config:, conn: None),
    connect:,
    disconnect:,
    set:,
    get:,
    delete:,
  )
}

fn connect(driver: Redis) -> Result(Redis, drivers.ConnectError(RedisError)) {
  case driver {
    Redis(config:, conn: None) -> {
      radish.start(
        config.host,
        config.port,
        redis_config_to_radish_start_options(config),
      )
      |> result.map(fn(conn) { Redis(config: config, conn: Some(conn)) })
      |> result.map_error(fn(err) {
        drivers.ConnectDriverError(StartError(err))
      })
    }
    Redis(config: _, conn: Some(_)) -> Error(drivers.AlreadyConnected)
  }
}

fn disconnect(
  driver: Redis,
) -> Result(Redis, drivers.DisconnectError(RedisError)) {
  case driver {
    Redis(config: config, conn: Some(conn)) -> {
      radish.shutdown(conn)
      Ok(Redis(config:, conn: None))
    }
    Redis(config: _, conn: None) -> Error(drivers.NotConnected)
  }
}

fn create_key(resource_type: String, key: String) -> String {
  resource_type <> ":" <> key
}

fn set(
  driver: Redis,
  resource_type: String,
  key: String,
  value: String,
  ttl_seconds: Option(Int),
) -> Result(Nil, cache.SetError(RedisError)) {
  let assert Redis(config:, conn: Some(conn)) = driver
  let key = create_key(resource_type, key)
  let set_result = case radish.set(conn, key, value, config.timeout) {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(cache.SetDriverError(radish_error_to_redis_error(err)))
  }

  use _ <- result.try(set_result)

  let ttl_result = case ttl_seconds {
    None -> radish.persist(conn, key, config.timeout)
    Some(ttl_seconds) -> radish.expire(conn, key, ttl_seconds, config.timeout)
  }

  case ttl_result {
    Ok(_) -> Ok(Nil)
    // This will only happen in a race condition where the key has been
    // deleted between the `set` and `expire`/`persist` calls
    Error(radish_error.NotFound) ->
      Error(cache.SetDriverError(UnknownResponseError))
    Error(err) -> Error(cache.SetDriverError(radish_error_to_redis_error(err)))
  }
}

fn get(
  driver: Redis,
  resource_type: String,
  key: String,
) -> Result(String, cache.GetError(RedisError)) {
  let assert Redis(config:, conn: Some(conn)) = driver
  let key = create_key(resource_type, key)
  let get_result = radish.get(conn, key, config.timeout)
  case get_result {
    Ok(value) -> Ok(value)
    Error(radish_error.NotFound) -> Error(cache.GotTooFewRecords)
    Error(err) -> Error(cache.GetDriverError(radish_error_to_redis_error(err)))
  }
}

fn delete(
  driver: Redis,
  resource_type: String,
  key: String,
) -> Result(Nil, cache.DeleteError(RedisError)) {
  let assert Redis(config:, conn: Some(conn)) = driver
  let key = create_key(resource_type, key)
  let delete_result = radish.del(conn, [key], config.timeout)
  case delete_result {
    Ok(_) -> Ok(Nil)
    Error(radish_error.NotFound) -> Ok(Nil)
    Error(err) ->
      Error(cache.DeleteDriverError(radish_error_to_redis_error(err)))
  }
}