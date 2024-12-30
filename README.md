# Pevensie Redis Driver

[![Package Version](https://img.shields.io/hexpm/v/pevensie_redis)](https://hex.pm/packages/pevensie_redis)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/pevensie_redis/)

The official Redis-compatible driver for
[Pevensie](https://github.com/Pevensie/pevensie). It provides driver implementations
for Pevensie modules to be used with Redis-compatible databases.

Currently provides drivers for:

- [Pevensie Cache](https://hexdocs.pm/pevensie/pevensie/cache.html)

## Getting Started

Configure your driver to connect to your database using the
[`RedisConfig`](https://hexdocs.pm/pevensie_redis/pevensie/redis.html#RedisConfig)
type. You can use the [`default_config`](https://hexdocs.pm/pevensie_redis/pevensie/redis.html#default_config)
function to get a default configuration for connecting to a local
Redis database with a timeout of 5000 milliseconds.

```gleam
import pevensie/redis.{type RedisConfig}

pub fn main() {
  let config = RedisConfig(
    ..redis.default_config(),
    host: "cache.pevensie.dev",
  )
  // ...
}
```

Create a new driver using one of the `new_cache_driver` function
provided by this module. You can then use the driver with Pevensie
Cache.

```gleam
import pevensie/redis.{type RedisConfig}
import pevensie/cache

pub fn main() {
  let config = RedisConfig(
    ..redis.default_config(),
    host: "cache.pevensie.dev",
  )
  let driver = redis.new_cache_driver(config)
  let pevensie_auth = cache.new(driver:)
  // ...
}
```

## Connection Management

Pevenise Redis uses [radish](https://github.com/gleam-lang/radish) to connect to Redis.
Radish works by spawning a Gleam OTP actor to for communication with Redis. As such,
the [`connect`](https://hexdocs.pm/pevensie/pevensie/cache.html#connect) function provided by Pevensie Cache
will start this actor. This can be called once on boot, and will be reused for the lifetime of the application.

The [`disconnect`](https://hexdocs.pm/pevensie/pevensie/auth.html#disconnect) function
will stop the actor.

Pevensie Redis uses the [radish](https://github.com/massivefermion/radish) library to
connect to Redis. Connection pooling is managed using [Bath](https://github.com/Pevensie/bath).

## Implementation Details

This driver aims to use Redis in a standard way, and will work with any
Redis-compatible database (our own test suite uses [Valkey](https://valkey.io/)).

### Pevensie Cache

Pevensie Cache uses a combination of a custom resource type and key to identify
values in the cache. In Redis, this is represented as a single key of the form
`<resource_type>:<key>`.

TTL on `SET` operations is managed via the `EXPIRE` and `PERSIST` commands. When
the `ttl_seconds` argument is not `None`, an `EXPIRE` command will be sent
after the `SET` operation. When the `ttl_seconds` argument is `None`, a `PERSIST`
command will be sent instead.

Both will use the `timeout` value provided in the configuration. This means that
`cache.set`, when called with the Redis driver, may take twice the configured
timeout to complete.

## Development

Tests rely on a local Redis-compatible database running on port 6379. The repo includes
a `compose.yaml` file to start a local Valkey instance for testing, but feel free to
use any Redis-compatible database you'd like.

Tests  can be run with:

```bash
gleam test
```
