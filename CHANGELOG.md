## v0.5.1

* Update dependencies 
  * add `:plug` to Mix's `extra_applications` for 1.7 compatibility.

## v0.5.0

* [B3 Single](https://cwiki.apache.org/confluence/display/ZIPKIN/b3+single+header+format) propagation format support.

## v0.4.0

* Support for automatically propagating the `Tapper.Id` to `Tapper.Ctx`: see the `contextual` property. #2. (HT @indrekj).

## v0.3.0 

* Add optional `path_redactor` hook for whenever `Plug.Conn.request_path` is used.
* when starting a trace, set the root span's name to HTTP method and path, e.g. "GET /foo/bar"; runs through redactor.
* Allow `debug` flag to be set in Application config via `:tapper_plug, :debug` for easier control #1 (HT @alexlafroscia).
