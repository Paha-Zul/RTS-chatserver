import tables, json, sequtils, sugar, options
import Messages, ChatMessages
from Users import User

type 
    ChannelNoExist* = object of Exception

type
    Channel* = ref object
        id:int64
        name:string
        users:seq[User]
        messages:ChatMessageSeq
        temp*:bool

    ChannelTable* = ref object
        channels:TableRef[string, Channel]

proc creatChannelTable*():ChannelTable = 
    return ChannelTable(channels: newTable[string, Channel](16))

proc name*(channel:Channel):string =
    return channel.name

proc createChannel*(channels:ChannelTable, name:string, temp:bool = false):Option[Channel] = 
    ## Attempts to create a channel and add it to the channel table. Returns
    ## some(channel) if successfull with the channel created and none(Channel)
    ## if the channel name already existed

    if channels.channels.hasKey(name):
        return none(Channel)

    let channel = Channel(id: 1, name: name, users: @[], messages: createChatMessageSeq(), temp:temp)
    channels.channels[name] = channel

    return some(channel)

proc removeChannel*(channels:ChannelTable, name:string) =
    channels.channels.del name

func getChannel*(channels:ChannelTable, name:string):Option[Channel] =
    ## Attempts to get a channel from a ChannelTable. Returns some(channel) if exists or
    ## none(Channel) if no channel with the `name` is found

    if channels.channels.hasKey(name):
        return some(channels.channels[name])
    return none(Channel)

func getChannelData*(channel:Channel):(JsonNode, JsonNode) =
    ## Gets the channel data from a specific channel. Returns a tuple of
    ## (messages, users) of a channel

    let history = %*channel.messages.getChatMessages() # Get all the chat messages
    let users = %*channel.users.map(user => user.name) # Get only the name from the sequence of User

    return (history, users)

func addMessageToChannel*(channel:Channel, message:ChatMessage) = 
    ## Adds a chat message to a channel
    channel.messages.addChatMessage message

proc addUserToChannel*(channel:Channel, user:User) =
    ## Adds a user to a channel
    channel.users.add user

proc removeUserFromChannel*(channel:Channel, fun: (User) -> bool) =
    channel.users = channel.users.filter(fun)

func getUserFromChannel*(channel:Channel, fun: (User) -> bool): Option[User] =
    for user in channel.users:
        if fun(user):
            return some(user)
        
    return none(User)

func getUsers*(channel:Channel):seq[User] =
    return channel.users
