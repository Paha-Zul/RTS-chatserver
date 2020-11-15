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
proc getChannelData*(channel:Channel):(JsonNode, JsonNode) =
    let history = %*channel.messages
    let users = %*channel.users.map(user => user.name)

    return (history, users)