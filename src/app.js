var createError = require('http-errors');
var express = require('express');
const config = require('./config');
const log = require('./logger');
const ps_ctlr = require("./ps_controller");
const xmlParser = require('./parser');
const reparser = require('../sc-db-parser/wrapper.js');
const baseMove = require('./database_move');
const fs = require('fs');
const iconv = require('iconv-lite');
var uniqid = require('uniqid');
var mongo = require('./mongoController');

var app = express();

app.use(express.json());

app.use(function (req, res, next) {
    log("NET", {req: req.body}, 'cyan',);
    next();
});
app.use((req, res, next) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'OPTIONS,GET,PUT,POST,DELETE');
    res.set("Access-Control-Allow-Headers", "Access-Control-Allow-Origin, Access-Control-Allow-Headers, Origin,Accept, X-Requested-With, Content-Type, Access-Control-Request-Method, Access-Control-Request-Headers");

    if (req.method == "OPTIONS") {
        log("app::", "app.use::options_filter:: Caught options message, responded with 200", 'cyan');
        res.send(200);
    } else {
        next();
    }
});

// USER ID CHECKING
app.use((req, res, next) => {
    if (req.originalUrl == "/api/login") {
        next();
        return;
    }
    if (req.originalUrl == "/api/register") {
        next();
        return;
    }
    if (req.originalUrl == "/api/log") {
        next();
        return;
    }
    if (req.originalUrl == "/api/report") {
        next();
        return;
    }
    if (req.originalUrl == "/api/get_nodelist") {
        next();
        return;
    }
    if (req.originalUrl == "/api/get_doctors") {
        next();
        return;
    }
    if (req.body.hasOwnProperty('user_id')) {
        if (mongo.check_user_id(req.body.user_id)) {
            next();
        } else {
            res.send({error: "wrong user_id provided"});
        }
    } else {
        res.send({error: "no user_id in request"});
    }
});

function createLog(req, body) {
    let now = new Date();
    let result = {
        route: req.originalUrl,
        method: req.method,
        user_id: req.body.user_id,
        body: body,
        date: now.toISOString()
    };
    log("app::use::", result);
    return result;
}

app.use((req, res, next) => {
    if ((req.body != undefined)&&(req.body != {})&&(req.body!= null)) {
        if (req.originalUrl != "/check") {
            mongo.logAPI(createLog(req, req.body));
        }
    }
    if ((res.body != undefined)&&(res.body != {})&&(res.body!= null)) {
        mongo.logAPI(createLog(req, res.body));
    }
    next();
});


// // catch 404 and forward to error handler
// app.use(function(req, res, next) {
//   next(createError(404));
// });



//получить новый psid для расчетов
app.post('/api/psid', function (req, res) {
    log("app::app/post:: ", " get psid request", req);
    ps_ctlr.getPsid(function (psid) {
        res.send({result: 'ok', psid: psid});
    }, {TOKEN: req.body.TOKEN});
});

app.post('/api/check', function(req, res) {
    ps_ctlr.checkPsid(req.body.psid, function (result) {
        if (result.hasOwnProperty('error')) {
            res.send({'error': result.error});
        } else {
            res.send({result: result.result, psid: req.body.psid});
        }
    }, {TOKEN: req.body.TOKEN, psid: req.psid});
});

//установить глобальные парметры
app.post('/api/preset', function (req, res) {
    //todo проверка на праивльность построения запроса
    ps_ctlr.preset(req.body.psid, req.body.preset, function (result) {
         if (result.hasOwnProperty('error')) {
             res.send({'error': result.error});
         } else {
             res.send({result: result.result, psid: req.body.psid});
         }
     }, req.body);
    //res.send({result: "ok"});
});

//установить параметр
app.post('/api/set', function (req, res) {
    //todo проверка на праивльность построения запрос
    ps_ctlr.set(req.body.psid, req.body.set, function (result) {
        if (result.hasOwnProperty('error')) {
            res.send({'error': result.error});
        } else {
            res.send({result: result.result, psid: req.body.psid});
        }
    }, req.body)
});

//произвести расчет, вернется список заболеваний и симптомов в формате xml
app.post('/api/calc', function (req, res) {
    ps_ctlr.calc(req.body.psid, req.body.set, function (result) {
        if (result.hasOwnProperty('error')) {
            log("app::/calc::error", result);
            mongo.logAPI(createLog(req, {'error': result.error}));
            res.send({'error': result.error});
        } else {
            log("app::/calc::result", result);
            //result.result = xmlParser(result.result);
            mongo.logAPI(createLog(req,{result: result.result, psid: req.body.psid}));
            res.send({result: result.result, psid: req.body.psid});
        }
    }, req.body);
});

app.post('/api/close', function (req, res) {
    log("app:: app/close::", "catch close event", "yellow");
    ps_ctlr.close(req.body.psid, function (result) {
        if (result.hasOwnProperty('error')) {
    res.send({'error': result.error});
} else {
    res.send({result: result.result});
}
}, req.body)
});


//вернуть результаты предыдущего расчета
app.post('/api/print', function (req, res) {

});

//TODO проверка домена атласа
// app.post('/register', function (req, res) {
//     if ((req.body.hasOwnProperty('email'))&&(req.body.hasOwnProperty('pass'))) {
//         let user_id = uniqid();
//         var result = mongo.register_user(user_id, {'email': req.body.email, 'pass': req.body.pass});
//         result.then((value) => {
//             if (value.hasOwnProperty("err_code")) {
//                 res.send(value);
//             } else {
//                 res.send({result: "User added", user_id: value.user_id});
//             }
//         })
//     } else {
//         res.send({'error':"Wrong request"});
//     }
// });

app.post('/api/register', function (req, res) {
    if (req.body.hasOwnProperty('email')) {
        let user_id = uniqid();
        let pass = uniqid();
        let date = Date.now().toString();
        var result = mongo.register_user(user_id, {'email': req.body.email, 'pass': pass, 'date': date});
        result.then((value) => {
            if (value.hasOwnProperty("err_code")) {
                 res.send(value);
            } else {
                 res.send({result: "User added", user_id: value.user_id});
            }
        });
    }
});

//TODO
app.post('/api/login', function (req, res) {
    if ((req.body.hasOwnProperty('email'))&&(req.body.hasOwnProperty('pass'))) {
        var result = mongo.login_user(req.body.email, req.body.pass);
        result.then((value) => {
            if (value.hasOwnProperty("err_code")) {
                res.send(value);
            } else {
                res.send({result: "user_got", user_id: value.user_id});
            }
        })
    } else {
        res.send({'error':"Wrong request"});
    }
});

app.post('/api/log', function (req, res) {
   mongo.logClient(req.body);
   res.send(200);
});

app.post('/report', function (req, res) {
    mongo.report(req.body);
    res.send(200);
});

app.post('/api/reparse', function (req, res) {
   if ((mongo.check_god_mode(req.body.user_id))&&(config.enviroment.GOD_MODE_ON)) {
        ps_ctlr.killAll();
        reparser.reparse_async().then(() => {
            baseMove().then(()=> {
                reparser.reparse_nodelist().then(() => {
                    ps_ctlr.restart();
                    res.send("OK");
                });
            });
        });
   } else {
       res.send({"err": "forbidden operation"});
   }
});

app.post('/api/test', function(req, res) {
    if ((mongo.check_god_mode(req.body.user_id))&&(config.enviroment.GOD_MODE_ON)) {
        ps_ctlr.test(req.body, (result) => {
            res.send(result);
        });
    } else {
        res.send({'err': 'forbidden operation'});
    }
});

app.post('/api/get_nodelist', function(req, res) {
    let nodelist = fs.readFileSync('nodelist.json', 'utf-8');
    let nodelist_json = JSON.parse(nodelist);
    let nodelist_filters = fs.readFileSync('nodelist_filters.json');
    let nodelist_filters_json = JSON.parse(nodelist_filters);
    res.send({nodelist: nodelist_json, filters: nodelist_filters_json});
    return;
});

app.post('/api/get_doctors', function(req, res) {
    let doctors = fs.readFileSync('doctors.json', 'utf-8');
    let doctors_json = JSON.parse(doctors);
    res.send(doctors_json);
    return;
});

app.post('/api/get_symptoms_citos', function(req, res) {
    let symptoms_citos = fs.readFileSync('symptoms_citos.json', 'utf-8');
    let symptoms_citos_json = JSON.parse(symptoms_citos);
    res.send(symptoms_citos_json);
    return;
});

app.listen(config.server.port, function () {
  console.log("Server started. Listening to port " + config.server.port);
  mongo.init();
  ps_ctlr.start({});
});

module.exports = app;
