#!/bin/sh

npm install && NODE_ENV=production node_modules/.bin/forever start -w --watchIgnore ".git/**/*" --watchIgnore "node_modules/**/*" -c node_modules/.bin/coffee server.coffee
