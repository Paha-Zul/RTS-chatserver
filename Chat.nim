import ws, asyncdispatch, asynchttpserver, json, tables, seqUtils, sugar, times, os, options
import Messages, Channel, Users, utils, ChatMessages

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
let context = Context(users: createUserTable(), messages: createChatMessageSeq(), channels: creatChannelTable())

# Handles the start of a connection. This is a user asking for a name
proc handleUserConnect(data:JsonNode, ws: WebSocket, context:Context) {.async.} =
    assert(data.hasKey("name"))

    let name = data{"name"}.getStr() # decodes the name
    let free = context.users.getUserByName(name).isNone

    # If free, create and assign the user
    if free:
        discard
        # let user = createUser(name, ws) # create our user object
        # context.users.addUserToTable(user)
        echo name & " is free";

    let returnData = Messages.nameAvailable(free, name)
    # Send the result
    asyncCheck ws.send($returnData)

# Handles an incoming message
proc handleUserMessage(data:JsonNode, ws:WebSocket, context:Context) {.async, gcsafe.} =
    assert(data.hasKey("name"))
    assert(data.hasKey("message"))

    let name = data["name"].getStr
    let user = context.users.getUserByName(name)
    
    # make sure our user is some
    if user.isSome:
        let user = user.get # Shadow our user
        let currChannel = context.channels.getChannel(user.currChannelName)
        let message = data["message"].getStr

        let m = createChatMessage(user.name, message, now().utc.format("yyyy-MM-dd:hh:mm:ss"))

        # Make sure our channel is some
        if currChannel.isSome:
            let currChannel = currChannel.get # Shadow our channel
            # let dataMessage = chatMessage(data["name"].getStr, data["message"].getStr) # Creates the message
            currChannel.addMessageToChannel m # Adds the message to the current channel

            let returnMessage = Messages.chatMessage(user.name, message)
            #brodcasts the message
            for other in currChannel.getUsers():
                if other.ws.readyState == Open:
                    asyncCheck other.ws.send($returnMessage)

# Handles when a user leaves a channel
proc leaveChannel(channel:Channel, user:User, context:Context) {.async, gcsafe.} =
    # Simply remove our user from the current channel via filter
    channel.removeUserFromChannel(u => u.name != user.name)
    
    # First notify all users of the current channel that we are leaving
    let userLeft = Messages.userLeft(user.name)

    # If the channel is temporary and we have no users left, remove the channel
    if channel.temp and channel.getUsers().len <= 0:
        echo "Channel has no users. Removing " & channel.name
        context.channels.removeChannel channel.name
    
    # Otherwise send out to all users that someone left
    else:
        for other in channel.getUsers():
            if other.ws.readyState == Open:
                asyncCheck other.ws.send($userLeft)

# Handles joining a channel for a user
proc joinChannel(channel:Channel, user:User, context:Context) {.async, gcsafe.} =
    # Then notify all new users we are joining in the next channel
    let userJoined = Messages.userJoined(user.name)
    for other in channel.getUsers():
        if other.ws.readyState == Open:
            asyncCheck other.ws.send($userJoined)

    # Then add our user to the next channel
    channel.addUserToChannel(user)
    let (messageHistory, users) = channel.getChannelData()

    let channelJoined = Messages.channelJoined(channel.name, messageHistory, users)
    if user.ws.readyState == Open:
        asyncCheck user.ws.send($channelJoined)

    user.currChannelName = channel.name

# data is expected to be {name, channel_name}
proc handleChangeChannel(data:JsonNode, ws:WebSocket, context:Context) {.async, gcsafe.} =
    # Validate that we can change channels
    try:
        # Make sure our json has the data we need
        assert(data.hasKey("name"), "Json data incomplete. 'name' doesn't exist")
        assert(data.hasKey("channel_name"), "Json data incomplete. 'channel_name' doesn't exist")
        assert(context.users.hasUser(data["name"].getStr), "User table does not contain user name '"&data["name"].getStr&"'")

        # Assemble the data we need
        # let nextChannel = Channel.channels.getOrDefault(data["channel_name"].getStr)
        let nextChannel = context.channels.getChannel(data["channel_name"].getStr)
        if nextChannel.isSome:
            let nextChannel = nextChannel.get
            let user = context.users.getUserByName(data["name"].getStr)
            if user.isSome:
                let user = user.get
                # let currChannel = Channel.channels.getOrDefault(user.currChannelName)
                let currChannel = context.channels.getChannel(user.currChannelName)

                # Only raise an exception if our last channel is not ampty but we can't find it
                if user.currChannelName != "" and currChannel.isNone:
                    raise newException(ChannelNoExist, "Channel that user is leaving does not exist")

                # Get the next channel name
                let nextChannelName = nextChannel.name

                # If our current channel is the same as next channel, don't bother changing
                if user.currChannelName == nextChannelName:
                    return

                # leave the current channel
                if currChannel.isSome:
                    await leaveChannel(currChannel.get, user, context)

                # Join the next channel
                await nextChannel.joinChannel(user, context)
            else:
                raise newException(Exception, "User with name " & data["name"].getStr & " does not exist")
        else:
            raise newException(ChannelNoExist, "Channel trying to be joined doesn't exist")

        
    except ChannelNoExist:
        echo "Major problem"
        echo getCurrentExceptionMsg()
    except AssertionError:
        echo getCurrentExceptionMsg()
    except Exception:
        echo getCurrentExceptionMsg()

# Handles when a user is fully connected. This will send message history and user data 
# to complete the process
# data expected to be {action, name}
proc handleConnected(data:JsonNode, ws:WebSocket, context:Context) {.async, gcsafe.} =
    assert(data.hasKey("name"))

    let message = connected()
    asyncCheck ws.send($message)

    # Make sure someone didn't connect before us with the same name
    if not context.users.hasUser(data["name"].getStr):
        # let socket =  UserSocket(ws:ws, id:range(high(int)))
        let user = createUser(data["name"].getStr, ws)
        context.users.addUserToTable(user)

        let data = %* {"name": data["name"], "channel_name": START_CHANNEL}

        await handleChangeChannel(data, ws, context)

# handles creating a channel on the server
proc handleCreateChannel(data:JsonNode, ws:WebSocket, context:Context) {.async, gcsafe.} =
    assert(data.hasKey("channel_name")) # The channel name
    assert(data.hasKey("name")) # The user name

    let channelName = data["channel_name"].getStr
    let temp = data["temp"].getBool
    
    if context.channels.createChannel(channelName, temp).isSome:
        await handleChangeChannel(%*{"channel_name": channelName, "name": data["name"].getStr}, ws, context)

proc removeUser(ws:WebSocket, context:Context) {.async, gcsafe.} =
    # let name = socketTable[ws.key] # Get the name
    let user = context.users.getUserBySocket(ws)
    echo "How many users do we have? " & $context.users.getUsers().len
    assert(user.isNone, "The websocket disconnecting never fully connected")

    if user.isSome:
        let user = user.get
        let channel = context.channels.getChannel(user.currChannelName)
        if channel.isSome:
            await leaveChannel(channel.get, user, context) # Remove the user from the channel
        
        # Delete from the user table
        context.users.removeUserFromTable user.name

        echo "Removing " & user.name
    else:
        echo "User doesn't exist"


proc cb(req: Request) {.async, gcsafe.} =
    if req.url.path == "/ws/chat":
        var ws = await newWebSocket(req) # Await a new connection
        try:
            while ws.readyState == Open:
                let (opcode, data) = await ws.receivePacket()
                try:
                    let json = parseJson(data)
                    let action = json{"action"}.getStr()

                    echo data

                    case action:
                        of "request_name":
                            await handleUserConnect(json, ws, context)
                        of "message":
                            await handleUserMessage(json, ws, context)
                        of "connected":
                            await handleConnected(json, ws, context)
                        of "request_new_channel":
                            await handleCreateChannel(json, ws, context)
                        of "switch_channel":
                            await handleChangeChannel(json, ws, context)
                except JsonParsingError:
                    echo "Parsing error on json"

        except WebSocketError:
            echo "socket closed:", getCurrentExceptionMsg()
            try:
                await removeUser(ws, context)
            except AssertionError:
                echo getCurrentExceptionMsg()
    else:
        await req.respond(Http404, "Not found")
        


discard context.channels.createChannel(START_CHANNEL) # Create our initial (and only for now) channel

echo "Server is started and waiting"

var server = newAsyncHttpServer()
waitFor server.serve(Port(9001), cb)