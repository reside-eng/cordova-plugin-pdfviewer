var exec = require('cordova/exec');

exports.downloadFile = function(options, success, error) {
  exec(success, error, 'PDFHandler', 'downloadFile', [options.url]);
};