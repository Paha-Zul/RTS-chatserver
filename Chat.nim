import ws, asyncdispatch, asynchttpserver, json, tables, seqUtils, sugar, times, os
import Messages, Channel, User, utils, ChatMessage

const START_CHANNEL = "General"

type
    Pair = ref object
        ws:WebSocket
        name:string

    # Context to pass to all of our functions to help not use global scoped variables
    Context = ref object
        users: UserTable
        messages: ChatMessageSeq
        channels: ChannelTable

# simple sequence of sockets
var connections = newSeq[Pair]() 

# Handles the start of a connection. This is a user asking for a name
proc handleUserConnect(data:JsonNode, ws: WebSocket) {.async.} =
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
proc handleUserMessage(data:JsonNode) {.async, gcsafe.} =
    let user:User = User.userTable[data["name"].getStr] # Get the user
    let currChannel:Channel = Channel.channels[user.currChannelName] # Get the current user's channel

    let m = createChatMessage(user.name, data["message"].getStr, now().utc.format("yyyy-MM-dd:hh:mm:ss"))

    let message = chatMessage(data["name"].getStr, data["message"].getStr) # Creates the message
    currChannel.messages.add $message # Adds the message to the current channel

    #brodcasts the message
    for other in currChannel.users:
        if other.ws.readyState == Open:
            asyncCheck other.ws.send($message)

# Handles when a user leaves a channel
proc leaveChannel(channel:Channel, user:User) {.async, gcsafe.} =
    # Simply remove our user from the current channel via filter
    channel.users = channel.users.filter(u => u.name != user.name)
    
    # First notify all users of the current channel that we are leaving
    let userLeft = Messages.userLeft(user.name)

    # If the channel is temporary and we have no users left, remove the channel
    if channel.temp and channel.users.len <= 0:
        echo "Channel has no users. Removing " & channel.name
        channels.del channel.name
    
    # Otherwise send out to all users that someone left
    else:
        for other in channel.users:
            if other.ws.readyState == Open:
                asyncCheck other.ws.send($userLeft)

# Handles joining a channel for a user
proc joinChannel(channel:Channel, user:User) {.async, gcsafe.} =
    # Then notify all new users we are joining in the next channel
    let userJoined = Messages.userJoined(user.name)
    for other in channel.users:
        if other.ws.readyState == Open:
            asyncCheck other.ws.send($userJoined)

    # Then add our user to the next channel
    channel.users.add(user)
    let (messageHistory, users) = channel.getChannelData()

    let channelJoined = Messages.channelJoined(channel.name, messageHistory, users)
    if user.ws.readyState == Open:
        asyncCheck user.ws.send($channelJoined)

    user.currChannelName = channel.name

# data is expected to be {name, channel_name}
proc handleChangeChannel(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    # Validate that we can change channels
    try:
        # Make sure our json has the data we need
        assert(data.hasKey("name"), "Json data incomplete. 'name' doesn't exist")
        assert(data.hasKey("channel_name"), "Json data incomplete. 'channel_name' doesn't exist")
        assert(userTable.hasKey(data["name"].getStr), "User table does not contain user name '"&data["name"].getStr&"'")

        # Assemble the data we need
        let nextChannel = Channel.channels.getOrDefault(data["channel_name"].getStr)
        let user = userTable[data["name"].getStr]
        let currChannel = Channel.channels.getOrDefault(user.currChannelName)

        # Only raise an exception if our last channel is not ampty but we can't find it
        if user.currChannelName != "" and currChannel == nil:
            raise newException(ChannelNoExist, "Channel that user is leaving does not exist")

        # Raise if the next channel wasn't found
        if nextChannel == nil:
            raise newException(ChannelNoExist, "Channel trying to be joined doesn't exist")

        # Get the next channel name
        let nextChannelName = if nextChannel == nil:
                                ""
                            else:
                                nextChannel.name

        # If our current channel is the same as next channel, don't bother changing
        if user.currChannelName == nextChannelName:
            return

        # leave the current channel
        if currChannel != nil:
            await leaveChannel(currChannel, user)

        # Join the next channel
        await nextChannel.joinChannel(user)
        
    except ChannelNoExist:
        echo "Major problem"
        echo getCurrentExceptionMsg()
    except AssertionError:
        echo getCurrentExceptionMsg()

# Handles when a user is fully connected. This will send message history and user data 
# to complete the process
# data expected to be {action, name}
proc handleConnected(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    let message = connected()
    asyncCheck ws.send($message)

    # Assign our name to the socket table
    connections.first(c => c.ws == ws).name = data["name"].getStr
    # connections.add Pair(ws:ws, name:data["name"].getStr)

    let data = %* {"name": data["name"], "channel_name": START_CHANNEL}

    await handleChangeChannel(data, ws)

# handles creating a channel on the server
proc handleCreateChannel(data:JsonNode, ws:WebSocket) {.async, gcsafe.} =
    assert(data.hasKey("channel_name")) # The channel name
    assert(data.hasKey("name")) # The user name

    let channelName = data["channel_name"].getStr
    let temp = data["temp"].getBool
    
    if createChannel(channelName, temp):
        await handleChangeChannel(%*{"channel_name": channelName, "name": data["name"].getStr}, ws)

proc removeUser(ws:WebSocket) {.async, gcsafe.} =
    # let name = socketTable[ws.key] # Get the name
    let socketUserPair = connections.first(x => x.ws == ws)
    assert(socketUserPair != nil, "The websocket disconnecting never fully connected")

    # Get the user by their websocket. This is more reliable (albeit more search intensive)
    let user = seqUtils.toSeq(User.userTable.values).first(u => u.ws == ws)
    # let user = User.userTable.getOrDefault(socketUserPair.name, nil) # get the user

    if user != nil:
        let channel = Channel.channels.getOrDefault(user.currChannelName)
        if channel != nil:
            await leaveChannel(channel, user) # Remove the user from the channel
        
        # Delete from the user table
        User.userTable.del user.name
    else:
        echo "User '"&socketUserPair.name&"' was not a real user"

    # socketTable.del name
    connections = connections.filter(x => x.ws != ws)
    
    
    echo "Removing " & socketUserPair.name

proc cb(req: Request) {.async, gcsafe.} =
    if req.url.path == "/ws/chat":
        var ws = await newWebSocket(req) # Await a new connection
        try:
            connections.add Pair(ws:ws, name:"")
            while ws.readyState == Open:
                let (opcode, data) = await ws.receivePacket()
                try:
                    let json = parseJson(data)
                    let action = json{"action"}.getStr()

                    echo data

                    case action:
                        of "request_name":
                            await handleUserConnect(json, ws)
                        of "message":
                            await handleUserMessage(json)
                        of "connected":
                            await handleConnected(json, ws)
                        of "request_new_channel":
                            await handleCreateChannel(json, ws)
                        of "switch_channel":
                            await handleChangeChannel(json, ws)
                except JsonParsingError:
                    echo "Parsing error on json"

        except WebSocketError:
            echo "socket closed:", getCurrentExceptionMsg()
            try:
                await removeUser(ws)
            except AssertionError:
                echo getCurrentExceptionMsg()
    else:
        await req.respond(Http404, "Not found")
        


discard createChannel(START_CHANNEL) # Create our initial (and only for now) channel

echo "Server is started and waiting"

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)