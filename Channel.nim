import tables, json, sequtils, sugar
import User, Messages

type 
    ChannelNoExist* = object of Exception

type
    Channel* = ref object
        id:int64
        name*:string
        users*:seq[User]
        messages*:seq[string]

var channels*:TableRef[string, Channel] = newTable[string, Channel](32)

proc createChannel*(name:string):bool = 
    if channels.hasKey(name):
        return false

    let channel = Channel(id: 1, name: name, users: @[], messages: @[])
    channels[name] = channel

    return true

# Changes the channel for a user
proc changeChannel*(userName:string, currChannelName:string, nextChannelName:string):(JsonNode, JsonNode) =
    # If our current channel doesn't exist somehow
    # We only need to check this if our current channel name is not empty. 
    if currChannelName != "" and not channels.hasKey(currChannelName):
        raise newException(ChannelNoExist, "User's current channel doesn't exist")

    # If our next channel doesn't exist somehow
    # If the next channel name is empty OR doesn't exist, its an error
    if nextChannelName == "" or not channels.hasKey(nextChannelName):
        raise newException(ChannelNoExist, "The channel trying to be joined doesn't exist")

    let nextChannel = channels[nextChannelName] # Get the next channel

    # For each user in the current channel, send the message that our changing user is leaving
    # for user in currchannel.users:
    #     let ws = user.ws
    #     asyncCheck ws.send($message)

    let history = %*nextChannel.messages
    let users = nextChannel.users.map(user => user.name)

    return (%*nextChannel.messages, %*users)