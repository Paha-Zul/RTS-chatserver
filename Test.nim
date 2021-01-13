import asyncdispatch, asynchttpserver, ws

proc main() {.async.} =
  var ws = await newWebSocket("ws://76.110.59.93:9001/ws/chat")
  await ws.send("Hi, how are you?")
  echo await ws.receiveStrPacket()
  ws.close()

waitFor main()