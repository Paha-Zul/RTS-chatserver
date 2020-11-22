
type 
    ChatMessage* = ref object
        username:string
        message:string
        timestamp:string

    ChatMessageSeq* = ref object
        messages:seq[ChatMessage]
    
proc createChatMessage*(username:string, message:string, time:string):ChatMessage =
    return ChatMessage(username:username, message:message, timestamp:time)

proc createChatMessageSeq*():ChatMessageSeq =
    ## Creates a returns a ChatMessageSeq
    return ChatMessageSeq(messages: @[])

proc addChatMessage*(chatMessageHolder: ChatMessageSeq, chatMessage:ChatMessage) =
    ## Adds a message to this holder
    chatMessageHolder.messages.add chatMessage

proc getChatMessages*(chatMessageHolder: ChatMessageSeq):seq[ChatMessage] =
    ## Returns the messages of this message holder
    return chatMessageHolder.messages