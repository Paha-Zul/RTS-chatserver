import json

proc userLeft*(userName:string):JsonNode  =
    return %* {"action": "user_left", "name": userName}

proc userJoined*(userName:string):JsonNode = 
    return %* {"action": "user_joined", "name": userName}

proc chatMessage*(userName:string, message:string):JsonNode = 
    return %* {"action": "message", "name": userName, "message": message}

proc channelJoined*(roomName:string, messageList:JsonNode, userList:JsonNode):JsonNode =
    return %* {"action": "channel_joined", "channel_name":roomName, "messages": messageList, "users": userList}

proc connected*():JsonNode = 
    return %* {"action": "connected"}

proc nameAvailable*(available:bool, name:string):JsonNode = 
    return %* {"action": "name_available", "result": available, "name": name}