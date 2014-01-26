#!/bin/sh

npm install && node_modules/.bin/forever start -w --watchIgnore ".git/**/*" --watchIgnore "node_modules/**/*" -c node_modules/.bin/coffee workstation.coffee
