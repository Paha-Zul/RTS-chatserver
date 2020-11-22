
type 
    ChatMessage = ref object
        username:string
        message:string
        timestamp:string

    ChatMessageSeq* = ref object
        message:seq[ChatMessage]
    
proc createChatMessage*(username:string, message:string, time:string):ChatMessage =
    return ChatMessage(username:username, message:message, timestamp:time)