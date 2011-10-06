var ddoc = { "_id": "_design/app"
           , "lists": { ports: portsList }
           , "views": { ports: { map: portsViewMap } }
           , "validate_doc_update": validateDocUpdate
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
                    , hostname: val.hostname
                    , ip: val.ip }
  }

  send(toJSON(out))
}

function portsViewMap (doc) {
  // doc is something like:
  // { _id: "isaacs.no.de"
  // , machine: { name: "isaacs.no.de"
  //            , mapi: "stuff..."
  //            , uuid: "etc" }
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
    emit(p, { port: p
            , targetPort: doc.ports[p]
            , server: doc.server
            , hostname: doc._id
            , ip: doc.ip })
  }
}

// docs look like this:
/*
{
  "_id": "observer.no.de",
  "_rev": "1-421f797836d6aafd788a51b8697dad7b",
  "owner": "170965cb-742c-4e87-83a9-fcdbc27969ec",
  "ip": "10.2.128.65",
  "ports": {
    "18777": 18777,
    "18780": 80,
    "18788": 22
  },
  "server": "server-uuid-2",
  "machine": {
    "id": "540175d3-e90d-48ff-9aa4-8e09f3cb0f02",
    "name": "observer.no.de",
    "type": "smartmachine",
    "state": "provisioning",
    "dataset": "sdc:sdc:nodejs:1.2.3",
    "ips": [
      "10.2.128.65"
    ],
    "memory": 128,
    "disk": 5120,
    "metadata": {},
    "created": "2011-08-26T23:45:37+00:00",
    "updated": "2011-08-26T23:45:37+00:00",
    "sshPort": 18788
  }
}
*/

function validateDocUpdate (doc, oldDoc, user, dbCtx) {
  if (doc._deleted) return

  function assert (ok, message) {
    if (!ok) throw { forbidden: message }
  }

  function isUuid (s) {
    return s &&
      s.match(/[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/i)
  }

  function isIp (s) {
    return s &&
      s.match(/[0-9]{1,3}(\.[0-9]{1,3}){3}/) &&
      s.split(".").filter(function (n, i) {
        n = parseInt(n, 10)
        return n > 0 && n < 256 &&
          (i !== 0 || (n !== 0 && n !== 127 && n !== 255))
      }).length === 4
  }

  function isNumber (n) {
    return typeof n === "number" && n === n
  }

  Array.isArray = Array.isArray || function (ar) {
    return ar instanceof Array || (
      ar &&
      typeof ar === "object" &&
      typeof ar.length === "number" )
  }

  assert(isUuid(doc.owner), "owner must be uuid")
  assert(isUuid(doc.server), "server must be uuid")
  assert(isIp(doc.ip), "ip must be ip")
  assert(doc.machine && typeof doc.machine,
         "machine must be object")
  assert(doc.machine.name === doc._id, "machine name must match _id")
  assert(isUuid(doc.machine.id), "machine id must be uuid")
  assert(Array.isArray(doc.machine.ips), "machine ips must be array")
  assert(isNumber(doc.machine.memory),
         "machine.memory must be number")
  assert(isNumber(doc.machine.disk),
         "machine.disk must be number")
  assert(isNumber(doc.machine.sshPort),
         "machine.sshPort must be number")

  if (isNaN(Date.parse("2011-08-26T23:45:37+00:00"))) {
    // old spidermonkeys are annoying.
    Date.parse = (function (orig) {
      return function (s) {
        return orig(s.replace(/\-/g, "/").replace(/T/, " ").replace(/\+[0-9]{2}:[0-9]{2}$/, ""))
      }
    })(Date.parse)
  }

  var c = Date.parse(doc.machine.created) || (new Date(doc.machine.created).getTime())
    , u = Date.parse(doc.machine.updated) || (new Date(doc.machine.updated).getTime())
  assert(isNumber(c), "machine.created must be valid date "+doc.machine.created+" "+c)
  assert(isNumber(u), "machine.updated must be valid date "+doc.machine.updated+" "+u)
  assert(u >= c, "machine.updated must be >= machine.created")

  assert(doc.ports && typeof doc.ports === "object", "ports must be object")
  assert(doc.ports[doc.machine.sshPort] === 22, "sshPort must be mapped to :22")
  var portBase = 16385;
  var portRange = 49152;
  for (var i in doc.ports) {
    assert(String(parseInt(i)) === i,
           "each key in ports must be simple integer " + i + String(parseInt(i)))
    assert(i >= portBase, "each port must be >= "+portBase)
    assert(i <= portBase + portRange, "each port must be <= "+
           (portBase + portRange))
    assert(parseInt(doc.ports[i]) === doc.ports[i],
           "each value in ports must be simple integer")
  }
}

// dump the JSON to send to couchdb
console.log(JSON.stringify(ddoc, function (k, v) {
  if (typeof v === "function") {
    return v.toString().replace(/^function [a-z_]+\(/i, "function (")
  }
  return v
}))
