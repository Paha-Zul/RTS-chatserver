import ws, asyncdispatch, asynchttpserver, json, tables, sequtils, sugar
import Messages, Channel, User

const START_CHANNEL = "General"

# simple sequence of sockets
var connections = newSeq[WebSocket]() 
var socketTable = newTable[string, string]()

# Handles the start of a connection. This is a user asking for a name
proc handle_connect(data:JsonNode, ws: WebSocket) {.async.} =
    let name = data{"name"}.getStr() # decodes the name
    let free = not userTable.hasKey(name) # Checks if the name is free

    # If free, create and assign the user
    if free:
        let user = createUser(name, ws) # create our user object
        userTable[name] = user # assigns the name to the table
        echo "added " & user.name

    let returnData = Messages.nameAvailable(free, name)
    # Send the result
    asyncCheck ws.send($returnData)

# Handles an incoming message
proc handle_message(data:JsonNode) {.async, gcsafe.} =
    let user:User = User.userTable[data["name"].getStr] # Get the user
    let currChannel:Channel = Channel.channels[user.currChannelName] # Get the current user's channel

    let message = chatMessage(data["name"].getStr, data["message"].getStr) # Creates the message
    currChannel.messages.add $message # Adds the message to the current channel

    #brodcasts the message
    for other in currChannel.users:
        if other.ws.readyState == Open:
            asyncCheck other.ws.send($message)

# data is expected to be {name, channel_name}
proc handle_channel_change(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    # Validate that we can change channels
    try:
        let nextChannel = Channel.channels.getOrDefault(data["channel_name"].getStr)
        let user = userTable[data["name"].getStr]
        let currChannel = Channel.channels.getOrDefault(user.currChannelName)

        # Only raise an exception if our last channel is not ampty but we can't find it
        if user.currChannelName != "" and currChannel == nil:
            raise newException(ChannelNoExist, "Channel that user is leaving does not exist")

        # Raise if the next channel wasn't found
        if nextChannel == nil:
            raise newException(ChannelNoExist, "Channel trying to be joined doesn't exist")

        let nextChannelName = if nextChannel == nil:
                                ""
                            else:
                                nextChannel.name

        if user.currChannelName == nextChannelName:
            return

        # Get the history and users from the next channel
        if nextChannel != nil:
            # Simply remove our user from the current channel via filter
            nextChannel.users = nextChannel.users.filter(u => u.name != user.name)
            
            # First notify all users of the current channel that we are leaving
            let userLeft = Messages.userLeft(user.name)
            for other in nextChannel.users:
                if other.ws.readyState == Open:
                    asyncCheck other.ws.send($userLeft)

        # Then notify all new users we are joining in the next channel
        let userJoined = Messages.userJoined(user.name)
        for other in nextChannel.users:
            if other.ws.readyState == Open:
                asyncCheck other.ws.send($userJoined)

        # Then add our user to the next channel
        nextChannel.users.add(user)
        let (messageHistory, users) = Channel.changeChannel(user.name, nextChannelName, nextChannel.name)

        let channelJoined = Messages.channelJoined(nextChannel.name, messageHistory, users)
        if ws.readyState == Open:
            asyncCheck ws.send($channelJoined)

        user.currChannelName = nextChannel.name
        
    except ChannelNoExist:
        echo "Major problem"
        echo getCurrentExceptionMsg()

# Handles when a user is fully connected. This will send message history and user data 
# to complete the process
# data expected to be {action, name}
proc handle_connected(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    let message = connected()
    asyncCheck ws.send($message)

    # Assign our name to the socket table
    socketTable[ws.key] = data["name"].getStr

    let data = %* {"name": data["name"], "channel_name": START_CHANNEL}

    await handle_channel_change(data, ws)


proc handle_create_channel(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    let channelName = data["channel_name"].getStr
    if createChannel(channelName):
        await handle_channel_change(%*{"channel_name": channelName, "name": data["name"].getStr}, ws)

proc cb(req: Request) {.async, gcsafe.} =
    if req.url.path == "/ws/chat":
        var ws = await newWebSocket(req) # Await a new connection
        try:
            connections.add ws # Add to the list
            socketTable[ws.key] = ""
            echo "key is " & ws.key

            while ws.readyState == Open:
                let (opcode, data) = await ws.receivePacket()
                try:
                    let json = parseJson(data)
                    let action = json{"action"}.getStr()

                    echo data

                    case action:
                        of "request_name":
                            await handle_connect(json, ws)
                        of "message":
                            await handle_message(json)
                        of "connected":
                            await handle_connected(json, ws)
                        of "request_new_channel":
                            await handle_create_channel(json, ws)
                        of "switch_channel":
                            await handle_channel_change(json, ws)
                except JsonParsingError:
                    echo "Parsing error on json"

                
        except WebSocketError:
            echo "socket closed:", getCurrentExceptionMsg()
            let name = socketTable[ws.key] # Get the name
            let user = User.userTable.getOrDefault(name, nil) # get the user
            if user != nil:
                let channel = Channel.channels[user.currChannelName] # Get the current channel
                channel.users = channel.users.filter(u => u.name != name) # remove them from the channel

            socketTable.del name
            connections = connections.filter(s => s != ws)
            User.userTable.del name
            
            echo "Removing " & name
    else:
        await req.respond(Http404, "Not found")
        
        

discard createChannel(START_CHANNEL) # Create our initial (and only for now) channel

echo "Server is started and waiting"

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)