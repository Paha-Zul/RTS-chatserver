import tables, ws, random, system

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