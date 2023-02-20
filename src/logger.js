/**
 * Created by Halck on 09.11.2018.
 */

const config = require("./config");

var log = function (caller, msg, color, options) {
    let color_start = "\x1b[0m", color_end = "\x1b[0m";
    if ((typeof msg == 'string')&&(msg.toLowerCase().includes("error"))) {
        color_start = "\x1b[31m";
        console.log(color_start + caller.padStart(config.logger.PAD_LENGTH, " ") + " " + msg + color_end);
    }

    if (color != undefined) {
        switch (color) {
            case 'red': color_start = "\x1b[31m";
            case 'yellow': color_start = "\x1b[33m";
            case 'cyan': color_start = "\x1b[36m";
        }
    }
    if (typeof msg == 'object') {
        console.log(color_start + caller.padStart(config.logger.PAD_LENGTH, " ") + " " + JSON.stringify(msg) + color_end);
    }
    if (typeof msg == 'string') {
        console.log(color_start + caller.padStart(config.logger.PAD_LENGTH, " ") + " " + msg + color_end);
    }


    if (options!=undefined) {
        if (options.hasOwnProperty("req")) {
            //console.log("".padStart(30, " ") + JSON.stringify(options.req.body));
        }
    }

    return;
};

module.exports = log;