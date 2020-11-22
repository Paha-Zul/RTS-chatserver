import tables, ws, random, system, options, sequtils, sugar
# import UserSocket

randomize()

type
    User* = ref object
        id*:int64
        name*:string
        ws*:WebSocket
        currChannelName*:string

    UserTable* = ref object
        users:TableRef[string, User]

proc createUser*(name:string, socket:WebSocket):User = 
    return User(id: rand(high(int)), name: name, ws: socket, currChannelName:"")

proc createUserTable*():UserTable =
    return UserTable(users: newTable[string, User](64))

proc getUserByName*(table:UserTable, name:string):Option[User] = 
    if table.users.hasKey(name):
        return some(table.users[name])
    return none(User)

proc getUserBySocket*(table:UserTable, ws:WebSocket):Option[User] = 
    for user in seqUtils.toSeq(table.users.values):
        if user.ws == ws:
            return some(user)

    return none(User)

proc getUserFromTable*(table:UserTable, fun: (User) -> bool): Option[User] =
    ## Get a user by an anonymous function. If getting a user by name, `getUserByName()` is greatly preferred

    for user in seqUtils.toSeq(table.users.values):
        if fun(user):
            return some(user)

    return none(User)

proc hasUser*(table:UserTable, name:string):bool =
    return table.users.hasKey(name)

proc addUserToTable*(users:UserTable, user:User) =
    users.users[user.name] = user

proc removeUserFromTable*(users:UserTable, name:string) =
    users.users.del name

proc getUsers*(users:UserTable):seq[User] = 
    return seqUtils.toSeq(users.users.values())