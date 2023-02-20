const mongoUser = "thesatanist";
const mongoPass = "fv017kpp";

const MongoClient = require('mongodb').MongoClient;
const uri = "mongodb+srv://thesatanist:fv017kpp@cluster0-qbsmj.mongodb.net/test?retryWrites=true";
const log = require('./logger');
const config = require('./config');
var postmark = require("postmark");

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////           VARIABLES                                 //////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

var client;
var post_client = new postmark.ServerClient("8813ffaf-51a7-48e9-80be-a3e34195c490");
var users = [];
var gods = [];

var send_mail = function (email, pass) {
    console.log("SENDING EMAIL TO " + email + " with pass " + pass);
    post_client.sendEmail({
        "From": "administration@atlas.ru",
        "To": email,
        "Subject": "Test",
        "HtmlBody": "<p>Здравствуйте!</p>\n" +
            "<br>\n" +
            "<p>Это письмо было создано автоматически после запроса на регистрацию в симптом-чекере Атлас.</p>\n" +
            "<p>Напоминаем, что симптом-чекер находится в режиме тестирования, поэтому мы будем благодарны любой обратной связи от вас.</p>\n" +
            "<br><p>Ваши данные для авторизации:</p>\n" +
            "<br>\n" +
            "<p><b>Логин</b>: " + email + "</p>\n" +
            "<p><b>Пароль</b>: " + pass + "</p>\n" +
            "<br>\n" +
            "<p>Если вы не инициировали отправку этого письма, то просто проигнорируйте его.\n</p>\n" +
            "<br><p>С наилучшими пожеланиями, </p><p>команда Атлас.</p>"
    });
};

var init = function () {
    console.log("Connecting mongo...");
    client = new MongoClient(uri, (err, db) => {
        console.log("Mongo connected.");
        console.log(err);
    });
    client.connect(err => {
        var collection = client.db("sch2").collection("users");
        collection.find({}).toArray((err, items) => {
            for (let i = 0; i < items.length; i++) {
                users.push(items[i].user_id);
                if (items[i].hasOwnProperty('god')&&(items[i].god)) {
                    gods.push(items[i].user_id);
                }
            }
            console.log("USERS");
            console.log(users);
            console.log("GODS");
            console.log(gods);
        });
        // perform actions on the collection object
    });

};

var register_user = function (user_id, user) {
    var result = new Promise((resolve, reject) => {
        var collection = client.db("sch2").collection("users");
        collection.find({'email': user.email}).toArray((err, items) => {
            // if (items.length > 0) {
            //     resolve({'error': "User already exist", "err_code": "1"})
            // }  else {
            //     collection.insertOne({'user_id': user_id, 'email': user.email, 'pass': user.pass});
            //     users.push(user_id);
            //     resolve({user_id: user_id});
            // }
            if (items.length > 0) {
                let minutes_passed = -(items[0]['date'] - Date.now()) / 1000 / 60;
                if (minutes_passed > config.postmark.sending_timeout) {
                    send_mail(items[0].email, items[0].pass);
                    collection.updateOne({'email': user.email}, {$set: {'date': Date.now().toString()}});
                    resolve({result: "ok"});
                } else {
                    console.log("Sending requests too often ", minutes_passed);
                    resolve({error: "", err_code: "2"});
                }
            } else {
                collection.insertOne({'user_id': user_id, 'email': user.email, 'pass': user.pass, 'date': user.date});
                users.push(user_id);
                send_mail(user.email, user.pass);
                resolve({user_id: user_id});
            }
        });
        //collection.insertOne({'user_id': user_id, 'email': user.email, 'pass': user.pass});
        //collection.find({}).toArray((err, items) => {console.log("ITEMS::"); console.log(items);});
    })
    return result;
};

var login_user = function (login, password) {
    var result = new Promise((resolve, reject) => {
        var collection = client.db("sch2").collection("users");
        collection.find({'email': login}).toArray((err, items) => {
            log("login_user::", "checking for user");
            console.log(items);
            if (items.length == 1) {
                if (items[0].pass == password) {
                    if (!check_user_id(items[0].user_id)) {
                        users.push(user_id);
                    }
                    resolve({'user_id': items[0].user_id});
                } else {
                    resolve({error: "wrong password", 'err_code': "2"});
                }
            } else {
                resolve({error: "no such user", 'err_code': "1"});
            }
        });
        //collection.insertOne({'user_id': user_id, 'email': user.email, 'pass': user.pass});
        //collection.find({}).toArray((err, items) => {console.log("ITEMS::"); console.log(items);});
    })
    return result;
};

var check_user_id = function (user_id) {
    log("check_user_id::", "");
    console.log(users);
    console.log(user_id);
    if (users.findIndex((el) => {
        return el == user_id;
    }) >= 0) {
        return true;
    }
    return false;
};

var logClient = function (log) {

    var collection = client.db("sch2").collection("logsClient");
    collection.find({'session': log.session}).toArray((err, items) => {
        console.log("LOGGER::", log);
        if (items.length > 0) {
            collection.updateOne({'session': log.session}, {$set: {'flow': log.flow}});
        } else {
            collection.insertOne(log);
        }
    });
};

var check_god_mode = function(user_id) {
    if (gods.findIndex((item) => {return item == user_id;}) >= 0){
        return true;
    } else {
        return false;
    };
};

var logAPI = function (log) {
    var collection = client.db("sch2").collection("logsAPI");
    collection.insertOne(log);
};

module.exports.init = init;
module.exports.register_user = register_user;
module.exports.login_user = login_user;
module.exports.check_user_id = check_user_id;
module.exports.logAPI = logAPI;
module.exports.logClient = logClient;
module.exports.check_god_mode = check_god_mode;