import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/result
import gleeunit
import gleeunit/should
import pevensie/cache
import pevensie/redis.{
  RedisConfig, default_config, redis_config_to_radish_start_options,
}
import radish

pub fn main() {
  // TODO: migrate to startest
  gleeunit.main()
}

pub fn config_conversion_test() {
  RedisConfig(
    host: "localhost",
    port: 6379,
    timeout: 5000,
    username: None,
    password: None,
  )
  |> redis_config_to_radish_start_options
  |> should.equal([radish.Timeout(5000)])

  RedisConfig(
    host: "localhost",
    port: 6379,
    timeout: 5000,
    username: Some("foo"),
    password: None,
  )
  |> redis_config_to_radish_start_options
  |> should.equal([radish.AuthWithUsername("foo", ""), radish.Timeout(5000)])

  RedisConfig(
    host: "localhost",
    port: 6379,
    timeout: 5000,
    username: Some("foo"),
    password: Some("bar"),
  )
  |> redis_config_to_radish_start_options
  |> should.equal([radish.AuthWithUsername("foo", "bar"), radish.Timeout(5000)])

  RedisConfig(
    host: "localhost",
    port: 6379,
    timeout: 5000,
    username: None,
    password: Some("bar"),
  )
  |> redis_config_to_radish_start_options
  |> should.equal([radish.Auth("bar"), radish.Timeout(5000)])
}

pub fn connection_test() {
  let client =
    redis.new_cache_driver(default_config())
    |> cache.new
  let assert Ok(client) = client |> cache.connect
  let assert Ok(_) = client |> cache.disconnect
}

fn get_test_client() {
  let assert Ok(client) =
    redis.new_cache_driver(default_config())
    |> cache.new
    |> cache.connect

  client
}

pub fn set_and_get_no_ttl_test() {
  let client = get_test_client()
  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: None,
    )

  let assert Ok("value") =
    client |> cache.get(resource_type: "type", key: "key")
}

pub fn set_and_get_with_ttl_test() {
  let client = get_test_client()
  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: Some(1),
    )

  process.sleep(1100)

  let assert Error(cache.GotTooFewRecords) =
    client |> cache.get(resource_type: "type", key: "key")
}

pub fn ttl_overrides_correctly_test() {
  let client = get_test_client()
  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: Some(100),
    )

  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: Some(1),
    )

  process.sleep(1100)

  let assert Error(cache.GotTooFewRecords) =
    client |> cache.get(resource_type: "type", key: "key")
}

pub fn ttl_clears_correctly_test() {
  let client = get_test_client()
  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: Some(1),
    )

  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: None,
    )

  process.sleep(1100)

  let assert Ok("value") =
    client |> cache.get(resource_type: "type", key: "key")
}

pub fn delete_test() {
  let client = get_test_client()
  let assert Ok(Nil) =
    client
    |> cache.set(
      resource_type: "type",
      key: "key",
      value: "value",
      ttl_seconds: Some(1),
    )

  let assert Ok(Nil) = client |> cache.delete(resource_type: "type", key: "key")

  let assert Error(cache.GotTooFewRecords) =
    client |> cache.get(resource_type: "type", key: "key")
}

pub fn delete_nonexistent_key_test() {
  let client = get_test_client()

  let assert Ok(Nil) =
    client
    |> cache.delete(resource_type: "type", key: "some_key_that_doesnt_exist")

  let assert Error(cache.GotTooFewRecords) =
    client
    |> cache.get(resource_type: "type", key: "some_key_that_doesnt_exist")
}
