# Opinionated HTTP

An opinionated HTTP Client library using convention over configuration.

Uses
* PersistentHTTP for http connection pooling.
* Semantic Logger for logging and metrics.
* Secret Config for its configuration.

By convention the following metrics are measured and logged:
*

PersistentHTTP with the following enhancements:
* Read config from Secret Config, just supply the `secret_config_path`.
* Redirect logging into standard Semantic Logger.
* Implements metrics and measure call durations.
* Standardized Service Exception.
* Retries on HTTP 5XX errors

# Example

# Configuration

# Usage

Create a new Opinionated HTTP instance.

Parameters:
  secret_config_prefix:
    Required
  metric_prefix:
    Required
  error_class:
    Whenever exceptions are raised it is important that every client gets its own exception / error class
    so that failures to specific http servers can be easily identified.
    Required.
  logger:
    Default: SemanticLogger[OpinionatedHTTP]
  Other options as supported by PersistentHTTP
  #TODO: Expand PersistentHTTP options here

Configuration:
   Off of the `secret_config_path` path above, Opinionated HTTP uses specific configuration entry names
   to configure the underlying HTTP setup:
      url: [String]
        The host url to the site to connect to.
        Exclude any path, since that will be supplied when `#get` or `#post` is called.
        Required.
        Examples:
          "https://example.com"
          "https://example.com:8443/"
      pool_size: [Integer]
        default: 100
      open_timeout: [Float]
        default: 10
      read_timeout: [Float]
        default: 10
      idle_timeout: [Float]
        default: 300
      keep_alive: [Float]
        default: 300
      pool_timeout: [Float]
        default: 5
      warn_timeout: [Float]
        default: 0.25
      proxy: [Symbol]
        default: :ENV
      force_retry: [true|false]
        default: true

Metrics:
  During each call to `#get` or `#put`, the following metrics are logged using the
