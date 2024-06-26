var express = require('express');
var _ = require('lodash');
var app = express();
app.get('/', function (req, res) {
  res.send('Hello World!');
  res.send(`Current timestamp is: ${_.now()}`);
});
app.listen(3000, function () {
  console.log('Example app listening on port 3000!');
});