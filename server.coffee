"use strict"

express = require("express")
os = require('os')
_ = require('underscore')
zookeeper = require('node-zookeeper-client')
Backbone = require('backbone')
iostream = require('socket.io-stream')
zookeeper = require('node-zookeeper-client')

app = express()
server = require("http").createServer(app)

app.set 'port', process.env.PORT or 3100
app.set 'endpoint', process.env.ENDPOINT or '/ws-proxy'
app.set 'zk_root', process.env.ZK_ROOT or '/remote/alive/workstation'
app.set 'zk_url', process.env.ZK_URL or "localhost:2181"
app.enable 'trust proxy'
app.use express.methodOverride()

if "development" is app.get("env")
  app.use express.errorHandler()
app.use app.router # api router

wss = {}
app.all "#{app.get 'endpoint'}/:mac/*", (req, res) ->
  return res.send(404) if req.params.mac not of wss
  stream = iostream.createStream()
  wss[req.params.mac].request
    path: "/api/#{req.params[0]}"
    method: req.method
    headers: req.headers
    query: req.query
  , stream, (stream, options) ->
    res.statusCode = options.statusCode
    res.set(options.headers)
    stream.on('error', (err) ->
      res.end(err)
    ).pipe res
  req.pipe stream

ip = do ->
  ifaces = os.networkInterfaces()
  for dev, addrs of ifaces when dev isnt 'lo'
    for addr in addrs when addr.family is 'IPv4' and addr.address isnt '127.0.0.1'
      return addr.address

http = do ->
  id = 0
  events = {}
  _.extend events, Backbone.Events
  (ss) ->
    ss.on 'response', (stream, options) ->
      events.trigger "id:#{options.id}", stream, options
    (options, stream, callback) ->
      id += 1
      options.id = id
      ss.emit 'http', stream, options
      events.once "id:#{id}", callback

zk = zookeeper.createClient(app.get('zk_url'))
zk.connect()
zk.once 'connected', ->
  zk.mkdirp app.get('zk_root'), (err) ->
    return process.exit(-1) if err
    zk_point = (mac) ->
      "#{app.get('zk_root')}/#{mac}"

    io = require('socket.io').listen(server)
    if "development" isnt app.get('env')
      io.set('log level', 1)
    io.of(app.get('endpoint')).on 'connection', (socket) ->
      ss = iostream(socket)
      request = http(ss)
      socket.on 'register', (msg, fn) ->
        info = new Backbone.Model
          ip: ip,
          mac: msg.mac
          uname: msg.uname
          api:
            status: msg.api?.status or 'down'
            path: "#{app.get('endpoint')}/#{msg.mac}"
            port: app.get('port')
            jobs: msg.api?.jobs ? []
            devices:
              android: msg.api?.devices?.android ? []
        wss[msg.mac] =
          request: request
          info: info
        zk.create zk_point(msg.mac), new Buffer(JSON.stringify info.toJSON()), zookeeper.CreateMode.EPHEMERAL, (err, path) ->
          return fn({returncode: -1, error: err}) if err and fn
          fn(returncode: 0) if fn

          info.on 'change', (event) ->
            zk.setData path, new Buffer(JSON.stringify info.toJSON()), (err, stat) ->
              return console.log(err) if err

          socket.on 'disconnect', ->  # remove zk node in case of disconnection
            delete wss[msg.mac]
            info.off()
            zk.remove path, (err) ->

          socket.on 'update', (msg, fn) ->  # update zk node
            info.set 'api',
              status: msg.api?.status or 'down'
              path: "#{app.get('endpoint')}/#{msg.mac}"
              port: app.get('port')
              jobs: msg.api?.jobs ? []
              devices:
                android: msg.api?.devices?.android ? []
            fn(returncode: 0) if fn

server.listen app.get("port"), ->
  console.log "Express server listening on port #{app.get('port')} in #{app.get('env')} mode."
