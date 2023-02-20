const fs = require('fs');
const config = require('./config.json');


var baseMove = function() {
    return new Promise((resolve, reject) => {
        var date = Date.now();
        //move old file
        fs.copyFile(config.enviroment.BASE_FOLDER + config.enviroment.BASE_DEFAULT_NAME, config.enviroment.BASE_OLD_FOLDER + config.enviroment.BASE_DEFAULT_NAME + date, () => {
            console.log("Old database moved to folder " + config.enviroment.BASE_OLD_FOLDER);
            fs.copyFile(config.enviroment.BASE_DEFAULT_NAME, config.enviroment.BASE_FOLDER + config.enviroment.BASE_DEFAULT_NAME, () => {
                resolve();
            })
        });
    })

};

module.exports = baseMove;