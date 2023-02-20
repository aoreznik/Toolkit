/**
 * Created by Halck on 14.11.2018.
 */

var xmlParser = require("fast-xml-parser");

var parseReqResult = function (input) {
  //console.log(input);
  return xmlParser.parse(input, {attributeNamePrefix: '', ignoreAttributes: false});
};

module.exports = parseReqResult;
