"use strict"

fs = require('fs')
sh = require('execSync')
io = require('socket.io-client')
request = require('request')

serverUrl = process.env.WS_URL or 'http://localhost:8000'
socket = io.connect(process.env.REGSERVER_URL or 'http://localhost:3100/ws-proxy')

iostream = require('socket.io-stream')
ss = iostream(socket)
ss.on 'http', (body, options) ->
  headers = {}
  headers[key] = value for key, value of options.headers when key in ['content-type', 'accept']
  rawData = ''
  body.on 'data', (chunk) ->
    rawData += chunk
  body.on 'end', ->
    opt =
      url: "#{serverUrl}#{options.path}"
      method: options.method or 'GET'
      qs: options.query or ''
      headers: headers
      body: rawData
    req = request(opt)
    stream = iostream.createStream()
    req.on('error', (err) ->
      stream.end(err)
    ).pipe stream
    req.on 'response', (response) ->
      ss.emit 'response', stream,
        statusCode: response.statusCode
        headers: response.headers
        id: options.id

socket.on 'connect', ->
  callback = (options) ->
    if options.returncode isnt 0
      return setTimeout ->
        register callback
      , 10000
    else
      timeoutId = setInterval update, 5000
      socket.on 'disconnect', -> clearTimeout timeoutId
  register callback

register = (cb) ->
  getInfo (info) ->
    socket.emit 'register', info, cb

update = ->
  getInfo (info) ->
    socket.emit 'update', info

info = 
  mac: fs.readFileSync('/sys/class/net/eth0/address').toString().trim()
  uname: sh.exec('uname -n -m -o').stdout.trim()
  api:
    status: 'down'
    jobs: []
    devices:
      android: []

getInfo = (cb) ->
  count = 3
  callback = (count)->
    cb info if count is 0
  request "#{serverUrl}/api/ping", (err, response, body) ->
    if err or response.statusCode isnt 200 or body isnt 'pong'
      info.api.status = 'down'
    else
      info.api.status = 'up'
    callback(--count)
  request "#{serverUrl}/api/0/devices", (err, response, body) ->
    if err or response.statusCode isnt 200
      info.api.devices.android = []
    else
      info.api.devices = JSON.parse(body)
    callback(--count)
  request "#{serverUrl}/api/0/jobs", (err, response, body) ->
    if err or response.statusCode isnt 200
      info.api.jobs = []
    else
      info.api.jobs = JSON.parse(body).jobs
    callback(--count)
