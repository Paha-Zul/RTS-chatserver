import tables, ws, random, system, options, sequtils, sugar

randomize()

type
    User* = ref object
        id*:int64
        name*:string
        ws*:WebSocket
        currChannelName*:string

    UserTable* = ref object
        users:TableRef[string, User]

# A table mapping *user name* to a *user object*
var userTable*: TableRef[string, User] = newTable[string, User](64) 

proc createUser*(name:string, socket:WebSocket):User = 
    return User(id: rand(high(int)), name: name, ws: socket, currChannelName:"")

proc createUserTable*():UserTable =
    return UserTable(users: newTable[string, User](64))

proc getUserByName*(table:UserTable, name:string):Option[User] = 
    if table.users.hasKey(name):
        return some(table.users[name])
    return none(User)

proc getUser*(table:UserTable, fun: (User) -> bool): Option[User] =
    ## Get a user by an anonymous function. If getting a user by name, `getUserByName()` is greatly preferred

    for user in seqUtils.toSeq(table.users.values):
        if fun(user):
            return some(user)

    return none(User)