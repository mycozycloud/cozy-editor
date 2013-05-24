# Make ajax request more easy to do.
# Expected callbacks: success and error
exports.request = (type, url, data, callback) ->
    $.ajax
        type: type
        url: url
        data: if data? then JSON.stringify data else null
        contentType: if data? then "application/json" else null
        success: (data) ->
            callback(null, data) if callback?
        error: ->
            if data.msg? and callback?
                callback new Error data.msg
            else if callback?
                callback new Error "Server error occured"

# Sends a get request with data as body
# Expected callbacks: success and error
exports.get = (url, callbacks) ->
    exports.request "GET", url, null, callbacks

# Sends a post request with data as body
# Expected callbacks: success and error
exports.post = (url, data, callbacks) ->
    exports.request "POST", url, data, callbacks

# Sends a put request with data as body
# Expected callbacks: success and error
exports.put = (url, data, callbacks) ->
    exports.request "PUT", url, data, callbacks

# Sends a delete request with data as body
# Expected callbacks: success and error
exports.del = (url, callbacks) ->
    exports.request "DELETE", url, null, callbacks
