var ddoc = { "_id": "_design/app"
           , "lists": { ports: portsList }
           , "views": { ports: { map: portsViewMap } }
           }


function portsList (head, req) {
  if (!req.query.server) {
    start({"code":"400", "headers": {"Content-Type": "application/json"}})
    send('{"error":"Please specify a server parameter"}')
    return
  }

  Object.keys = Object.keys
    || function (o) { var a = []
                      for (var i in o) a.push(i)
                      return a }

  start({"code": 200, "headers": {"Content-Type": "application/json"}})

  var row
    , out = {}
    , server = req.query.server

  while (row = getRow()) {
    var val = row.value
    if (val.server !== server) continue

    // should never happen, but just in case, let's be aware of it.
    if (out.hasOwnProperty(val.port)) {
      out.errors = out.errors || []
      out.errors.push({ error: "conflict"
                      , port: val.port
                      , data: val })
      continue
    }

    out[val.port] = { port: val.targetPort
                    , hostname: row.id
                    , ip: val.ip }
  }

  send(toJSON(out))
}

function portsViewMap (doc) {
  // doc is something like:
  // { _id: "isaacs.no.de"
  // , machines: { name: "isaacs.no.de"
  //             , mapi: "stuff..."
  //             , uuid: "etc" }
  // , server: "compute-node-uuid"
  // , ip: :"10.2.123.45"
  // , ports: { 54312: 22, 51337: 51337, 58080: 80 } }
  //
  // Ports is a list of public:private mappings.
  // They get one for ssh on port 22, one that proxies directly for
  // whatever they feel like using it for (generic TCP, etc.) and another
  // that maps directly to port 80 for testing http without the http-proxy.
  //
  // This emits something data for the portsList function.

  for (var p in doc.ports) {
    emit(doc._id, { port: p
                  , targetPort: doc.ports[p]
                  , server: doc.server
                  , ip: doc.ip })
  }
}

// dump the JSON to send to couchdb
console.log(JSON.stringify(ddoc, function (k, v) {
  if (typeof v === "function") return v.toString()
  return v
}))
