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

