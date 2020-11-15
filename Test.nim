import asyncdispatch, httpclient, json

proc asyncProc(): Future[string] {.async.} =
    var client = newAsyncHttpClient()
    # var data = newMultipartData()
    # data["messsage"] = "Hey this is a test message"
    let data = %* {"username": "paha", "token": 123, "message": "something or other"}
    echo data
    return await client.postContent("http://127.0.0.1:9000", body = $data)
    # return await client.getContent("127.0.0.1:8080")

echo waitFor asyncProc()