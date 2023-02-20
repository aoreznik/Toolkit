/**
 * Created by Halck on 09.11.2018.
 */

const config = require("./config.json");
const net = require('net');
const util = require('util');
const log = require("./logger");
const xmlParser = require('./parser');
const tests = require('./tests.json');

const {spawn} = require('child_process');

var PULL_SIZE_REQUIRED = (config.process.PULL_SIZE_REQUIRED) || (5);
var PULL_SIZE_CURRENT = 0;
var BUSY_CURRENT = 0;
var port_low = config.process.port_low;
var port_high = config.process.port_high;

var users = new Map([]); //{ psid , port , kicker , log }
var usersCounter = 0;
var pss = new Map([]);
var blockAppending = false;

var start = async function (options) {

    // Used to set PULL_SIZE from app.js. Removed cause too many places where PULL_SIZE setted
    // if ((options != undefined)&&(options.hasOwnProperty("N"))) {
    //   PULL_SIZE_REQUIRED = options.N;
    // }

    if (port_high - port_low < PULL_SIZE_REQUIRED) {
        log("ps_controller:start", "error. Required pull size is too big for setted port range");
        return -1;
    }

    appendToPull(PULL_SIZE_REQUIRED);

    availabilityChecker();
};

var appendToPull = async function (N) {
    if (blockAppending) {
        log("ps_ctrl::", "Appending to pull prevented due to database renewal");
        return;
    }
    let started = 0;
    for (let i = port_low; i < port_high - 90; i++) {
        if (!pss.has(i)) {
            let tmp = await createProcess(i);
            if (tmp == 1) started++;
        }

        if (started == N) break;
    }
};

var onProcessClose = function (port, options) {

    if (blockAppending) {
        log("ps_ctrl::", "Appending to pull prevented due to database renewal");
        return;
    }

    let ps = pss.get(port);

    //todo предусмотреть нормальне убийство сокета при неожиданном завершении процесса
    try {
        //pss.socket.destroy();
    } catch (ex) {

    }
    createProcess(port);
};

var createProcess = async function (port, options) {

    if (blockAppending) {
        log("ps_ctrl::", "Appending to pull prevented due to database renewal");
        return;
    }

    let ps = null;

    if (!pss.has(port)) {
        pss.set(port, {});
    }
    ps = pss.get(port);

    ps.busy = false;
    ps.port = port;
    ps.socket = null;

    ps.process = spawn(config.process.SC_PATH, ["--mode", 1, "--port", port, "--base", config.enviroment.BASE_FOLDER + "base.refactor.exp.json"]);
    ps.process.on('error', function (err) {
        log("ps_controller:createProcess", "Error in process on port " + ps.port);
    });

    try {
        ps.process.on('close', function (err) {
            log("ps_controller:createProcess", "Process on port " + ps.port + " closed");
            onProcessClose(ps.port);
        });

        ps.process.stdout.on("data", function (data) {
            if (config.logger.PROCESS_OUTPUT) {
                //log("ps::" + ps.port, data.toString(), 'yellow');
            }
        });

        pss.set(port, ps);

        log("ps_ctrl:createProcess", "Process for port " + port + " created.");

        return 1;
    } catch (ex) {
        return -1;
    }

};

//выделение процесса производится с открытием сокета, одновременно запускается таймер на событие kick
//выделение производится по токену

var openSocket = async function (port, callback, options) {

    let result = new Promise((resolve, reject) => {

        let ps = pss.get(port);
        ps.busy = false;
        ps.TOKEN = options.TOKEN;
        pss.set(port, ps);

        var client = new net.Socket();

        client.on('data', function (data) {
            //log("ps_controller:openSocket", "Data from port " + port + " recieved: " + data);
        });

        client.on('error', function () {
            reject(-1);
            log("ps_controller:openSocket", "Error on port " + port);
        });

        client.on('close', function () {
            log("ps_controller:openSocket", "Connection on port " + port + " closed");
        });

        client.connect(port, '127.0.0.1', function () {
            log("ps_controller:openSocket", "Socket for port " + port + " open");
            ps.socket = client;
            pss.set(port, ps);
            resolve(1);
        });

    });

    return result;

};

//PROCESSES HELPER

var setBusy = function (port, psid) {
    let res = pss.get(port);

    if (res.busy) {
        return false;
    }
    res.busy = true;
    if (psid != null) {
        let user = users.get(psid);
        clearTimeout(user.kicker);
        user.kicker = setTimeout(() => {
            kicker(psid, {})
        }, config.users.KICKER_TIMER * 60 * 1000);
    }
    pss.set(port, res);
    return true;
};

var setFree = function (port, psid) {
    let res = pss.get(port);
    res.busy = false;
    pss.set(port, res);
};

var setSocketFree = function (port, psid) {
    let res = pss.get(port);
    //TODO разобраться какого хера от команды clr закрывается процесс???
    req(port, 'clr', {psid: psid});
    try {
        res.socket.destroy();
    } catch (ex) {
        log("setSocketFree", "unable to destroy socket on port=" + port + " psid=" + psid);
    }

    res.socket = null;
    pss.set(port, res);
};

// USERS HELPERS

var upUsersCounter = function () {
    usersCounter++;
    if (usersCounter > 1000) {
        usersCounter = 0;
    }
};

var kicker = function (psid, options) {
    log("ps_ctrl::kicker", users.toString(), "yellow");
    if (users.has(psid)) {
        let res = users.get(psid);
        let port = res.port;
        setSocketFree(port, psid);
        clearTimeout(res.kicker);
        users.delete(psid);
        if (options.hasOwnProperty('force')) {
            log("ps_ctrl::kicker", "Closed event catched", 'yellow');
        } else {
            log("ps_ctrl::kicker", "User kicked due to inactivity", 'yellow');
        }
    } else {
        log("ps_ctrl::kicker", "Error. No user to kick psid " + psid);
    }
};

var addPsid = function (port, options) {
    upUsersCounter();
    var kickerTmp = setTimeout(() => {
        kicker(usersCounter, {})
    }, config.users.KICKER_TIMER * 60 * 1000);
    users.set(usersCounter, {psid: usersCounter, port: port, kicker: kickerTmp, logs: []});
    return usersCounter;
};

var getPortFromPsid = function (psid, options) {
    if (!users.has(psid)) {
        return {error: "No such psid registered"};
    }
    var res = users.get(psid);
    return res.port;
};

var logCommand = function (psid, cmd, options) {
    let res = users.get(psid);
    res.log.push(cmd);
    users.set(psid, res);
};

var getPsid = async function (callback, options) {
    availabilityCheck();
    for (let key of pss.keys()) {
        let ps = pss.get(key);
        if ((ps.socket == null)) {
            var socket_result = await openSocket(ps.port, null, options);
            ps = pss.get(key);
            //todo вставить удаление процесса при отрицательном колбеке от чека, нахуй он такое нужен, не отвечающий, тем более что он занят
            options.psid = null;
            let chk_result = await chk(ps.port, options);
            if (!chk_result.hasOwnProperty("error")) {
                callback(addPsid(chk_result.psid));
                return;
            }
        }
    }
};

var checkRequestData = function (psid, callback, options) {

    var port = getPortFromPsid(psid);

    if (port.hasOwnProperty('error')) {
        callback(port);
        return port;
    }

    if (!pss.has(port)) {
        let err = {error: 'No such psid registered'};
        callback({error: 'No such psid registered'});
        return err;
    }
    let ps = pss.get(port);

    //проверяем что к нам обратился именно владелец нужного токена
    if ((ps.TOKEN != options.TOKEN)) {
        let err = {error: 'Wrong TOKEN provided.'};
        callback(err);
        return err;
    }
    return port;
}

var checkPsid = async function (psid, callback, options) {

    options.psid = psid;

    var port = checkRequestData(psid, callback, options);

    if (port < -1) return;
    let chk_result = await chk(port, options);
    if (!chk_result.hasOwnProperty('error')) {
        callback({result: 'ok'});
    } else {
        callback(chk_result);
    }
};

//preset
var preset = async function (psid, sets, callback, options) {

    var port = checkRequestData(psid, callback, options);

    let ps = pss.get(port);
    //todo проверка на правильность построения запроса
    let cmd = "preset";
    for (let set of sets) {
        cmd += " " + set.n + " " + set.s;
    }
    var set_result = await req(port, cmd, {psid: psid});
    if (set_result.includes("ok")) set_result = "ok";
    if (set_result != 'ok') {
        callback({error: 'Unable to set entered nodes'});
    } else {
        callback({result: 'ok'});
    }
};

//todo исправить описание функции preset в msdn, добавить флаг или ввести новую функцию. сделать регекспы
var set = async function (psid, sets, callback, options) {

    var port = checkRequestData(psid, callback, options);

    let ps = pss.get(port);
    //todo проверка на правильность построения запроса
    let cmd = "set";
    let sets_cmds = [];
    for (let set of sets) {

        if (set.hasOwnProperty('severity')) {
            sets_cmds.push("sets " + set.n + " " + set.s + " " + set.severity);
        } else {
            cmd += " " + set.n + " " + set.s;
        }
    }

    console.log("sets_cmds = ");
    console.log(sets_cmds);
    if (cmd != "set") {
        var set_result = await req(port, cmd, {psid: psid});
        if (set_result.includes("ok")) set_result = "ok";
    }
    for (let sets_cmd of sets_cmds) {
        let sets_result = await req(port, sets_cmd, {psid: psid});
        if (sets_result.includes("ok")&&(set_result)) set_result = "ok";
        else set_result = "notok";
    }
    if (set_result != 'ok') {
        callback({error: 'Unable to set entered nodes'});
    } else {
        callback({result: 'ok'});
    }
};


var add_objects = function(o1, o2) {
    var result = {};
    if ((typeof (o1) == "object")&&(typeof (o1) == "object")) {
        var all_keys = [].concat(Object.keys(o1)).concat(Object.keys(o2));
        for (key of all_keys) {
            if (o1.hasOwnProperty(key)&&o2.hasOwnProperty(key)) {
                result[key] = add_objects(o1[key], o2[key]);
            }
            if (o1.hasOwnProperty(key)&&!o2.hasOwnProperty(key)) {
                result[key] = o1[key];
            }
            if (!o1.hasOwnProperty(key)&&o2.hasOwnProperty(key)) {
                result[key] = o2[key];
            }
        }
        return result;
    }
    if  ((typeof (o1) == "number")&&(typeof (o2) == "number")) {
        return o1 + o2;
    }
    if  ((typeof (o1) == "string")&&(typeof (o2) == "string")) {
        return o1 + o2;
    }
    return "error";
};

var calc = async function (psid, sets, callback, options) {

    var port = checkRequestData(psid, callback, options);

    if (port.hasOwnProperty("error")) return;

    let ps = pss.get(port);

    let cmd = 'calc';
    let calc_results = {};

    //var calc_result = await req(port, cmd, {psid: psid});

    function addResult(result) {
        result = xmlParser(result)['result'];
        if ((result == undefined) || (result.diseases == undefined)) {
            return;
        }
        if (result.diseases == '') return;
        if (!Array.isArray(result.diseases.d)) {
            result.diseases.d = [result.diseases.d];
        }
        for (let i = 0; i < result.diseases.d.length; i++) {
            let el = result.diseases.d[i];
            if (calc_results.result.hasOwnProperty(el.n)) {
                calc_results.result[el.n] += Number(el.s);
            } else {
                calc_results.result[el.n] = Number(el.s);
            }
        }
        // if (result.end.info['#text'] != undefined) {
        //     let infos = result.end.info['#text'].split('\n');
        //     for (let i = 0; i < infos.length; i++) {
        //         let num = infos[i].split('-')[0];
        //         let value = Number(infos[i].split('-')[1]);
        //         if (calc_results.info.hasOwnProperty(num)) {
        //             calc_results.info[num] += value;
        //         } else {
        //             calc_results.info[num] = value;
        //         }
        //     }
        // }
        if ((result.info != undefined) && (result.info.i != undefined)) {
            if (!Array.isArray(result.info.i)) {
                result.info.i = [result.info.i];
            }
            let infos = result.info.i;
            for (let i = 0; i < infos.length; i++) {
                let num = infos[i].n;
                let value = infos[i].s;
                if (calc_results.info.hasOwnProperty(num)) {
                    calc_results.info[num] += value;
                } else {
                    calc_results.info[num] = value;
                }
            }
        }
    }

    function div_object(o, mul) {

        let all_keys = Object.keys(o);

        if (typeof o == "number") {
            return Math.round(o / mul * 1000) / 1000;
        }
        if ((o == "inf")||(o == "-nan(ind)")) {
            return 1;
        }
        for (let key of all_keys) {
            console.log(key);
            o[key] = div_object(o[key], mul);
        }
        return o;
    }

    function averageResults() {
        // let arr_key = Object.keys(calc_results.result);
        // for (let i = 0; i < arr_key.length; i++) {
        //     let key = arr_key[i];
        //     calc_results.result[key] = calc_results.result[key] / config.calculations.CALC_MULTIPLIER;
        //     calc_results.result[key] = Math.round(calc_results.result[key] * 1000) / 1000;
        // }

        calc_results = div_object(calc_results, config.calculations.CALC_MULTIPLIER)
    }

    function reformatResults() {
        let results = [];
        let infos = [];
        let arr_key = Object.keys(calc_results.result);
        for (let i = 0; i < arr_key.length; i++) {
            let key = arr_key[i];
            results.push({'n': key, 's': calc_results.result[key]});
        }
        arr_key = Object.keys(calc_results.info);
        for (let i = 0; i < arr_key.length; i++) {
            let key = arr_key[i];
            infos.push({'n': key, 's': calc_results.info[key]});
        }
        calc_results['diseases'] = results;
        calc_results.result = [];
        calc_results.info = infos;
    }

    function reformatXMLResult(res) {
        if (!res.hasOwnProperty('diseases')||!res.hasOwnProperty('info')) {
            return {};
        }
        res["diseases"] = res["diseases"]["d"];
        res["symptoms"] = {};
        res["info"] = res["info"]["i"];
        let diseases = {};
        let info = {};
        if (!Array.isArray(res['diseases'])) res['diseases'] = [res['diseases']];
        console.log(JSON.stringify(res));
        for (let d of res['diseases']) {
            let rel_info = {};
            if (Array.isArray(d['rel_info'])) {
                for (let r of d['rel_info']) {
                    rel_info[r['index']] = r['info'];
                }
            } else {
                if (d['rel_info'] != undefined) {
                    rel_info[d['rel_info']['index']] = d['rel_info']['info'];
                }
            }

            diseases[d["n"]] = {s: d["s"], rel_info: rel_info};
        }
        if (res['info'] != undefined) {
            if (!Array.isArray(res['info'])) res['info'] = [res['info']];
            for (let i of res['info']) {
                info[i["n"]] = {s: i["s"]};
            }
        } else {
            res['info'] = [];
        }


        res['diseases'] = diseases;
        res['info'] = info;

        return res;
    }

    function reformatAfterAddition(res) {
        let diseases = res['diseases'];
        let infos = res['info'];
        let diseases_new = [];
        let infos_new = [];
        for (let key of Object.keys(diseases)) {
            diseases_new.push({n: Number(key), s: diseases[key]['s'], rel_info: diseases[key]['rel_info']});
        }

        for (let key of Object.keys(infos)) {
            infos_new.push({n: Number(key), s: infos[key]['s']});
        }
        res['diseases'] = diseases_new;
        res['info'] = infos_new;
        return res;
    }

    for (let i = 0; i < config.calculations.CALC_MULTIPLIER; i++) {
        var calc_result = await req(port, cmd, {psid: psid});
        //addResult(calc_result);
        calc_results = add_objects(reformatXMLResult(xmlParser(calc_result)['result']), calc_results);
    }

    averageResults(calc_results);
    calc_results = reformatAfterAddition(calc_results);

    //calc_results = calc_results['result'];
    //reformatResults();
    console.log("AFTER REFORMATTING");
    console.log(JSON.stringify(calc_results));
    calc_results.diseases.sort((a, b) => {
        return b.s - a.s;
    });

    log("calc::", "calc_results::", "red");

    if (calc_result.hasOwnProperty("error")) {
        callback(calc_results);
    } else {
        callback({result: calc_results});
    }
};

var req = function (port, cmd, options) {
    let result = new Promise((resolve, reject) => {
        console.log(cmd);
        log("ps::req", port, "yellow");
        let ps = pss.get(port);

        if (ps == undefined) {
            log("ps::req", "no psid on port " + port, "red");
            resolve({"error": "No such psid registered"});
        }
        let socket = ps.socket;

        if (!setBusy(port, options.psid)) {
            resolve({error: "PSID is busy for now. Try request later."});
        }

        if ((socket == undefined) || (socket == null)) resolve({error: "No socket available"});
        socket.write(cmd);

        let timer = setTimeout(() => {
            resolve(null);
        }, 20000);

        socket.on('data', (res) => {
            setFree(port);
            clearTimeout(timer);
            //log("ps_ctlr:req", "Response from ps " + res);
            res = res + "";
            try {
                resolve(res)
            } catch (ex) {
                log("ps_ctlr:req", "Error, unable to send response.");
            }
            socket.removeAllListeners('data');
        });
    });

    return result;
};

var chk = async function (port, options) {
    let result = new Promise((resolve, reject) => {

        let reqResult = req(port, 'chk', options);
        reqResult.then((res) => {
            if (!res.hasOwnProperty("error")) {
                resolve({result: 'ok', psid: port});
            } else {
                resolve(res);
            }
        });
    });
    return result;
};

var close = function (psid, callback, options) {
    kicker(psid, {force: true});
    //todo добавить обработку ошибок убиения
    callback({result: 'Your session closed'});
};

var availabilityCheck = function () {
    let available = 0;
    for (let key of pss.keys()) {
        let ps = pss.get(key);
        if ((ps.socket == null)) {
            available++;
        }
    }
    log("checkAvailability", "pss available: " + available);
    if (available < config.process.PULL_SIZE_GAP) {
        appendToPull(config.process.PULL_SIZE_GAP);
        log("ps_ctrl:checkAvailability", "appending new pss to pull: " + config.process.PULL_SIZE_GAP, 'cyan');
    }
}

var availabilityChecker = function () {
    setTimeout(availabilityCheck, config.process.availability_timeout * 60 * 1000);
};

var killAll = function () {
    blockAppending = true;
    for (let i = port_low; i < port_high - 90; i++) {
        if (pss.has(i)) {
            let ps = pss.get(i);
            ps.process.kill();
            ps.process = null;
            if (ps.socket != null) {
                ps.socket.destroy();
                ps.socket = null;
            }
            pss.delete(i);
            log("ps_ctrl::", "process " + i + " killed");
        }
    }
};

var restart = function () {
    blockAppending = false;
    log("ps_ctrl::","RESTARTING ALL PROCESSES");
    availabilityCheck();
};

var test = async function (reqopt, callback) {
    let final_result = [];

    for (let i = 0; i < tests.tests.length; i++) {
        let psid = -1;
        let test = tests.tests[i];
        let setCounter = 0;
        await getPsid((gotPsid) => {
            psid = gotPsid;
        }, reqopt);

        let port = await checkRequestData(psid, (p)=>{}, reqopt);
        if (port.hasOwnProperty("error")) return;
        //Set complaints
        let complaints = test.complaints;
        for (let j = 0; j < complaints.length; j++) {
            await req(port, 'set ' + complaints[j] + " 0", {});
        }
        let symptoms = test.symptoms;
        let max_questions = 10;
        let result = {};
        for (let j = 0; j < max_questions; j++) {
            await calc(psid, {}, (res)=>{result = res.result}, reqopt);
            let info = result.info[0];
            if (info != undefined) {
                if (symptoms.find((item) => {return item == info.n;})) {
                    await req(port, 'set ' + info.n + " 0", {});
                } else {
                    await req(port, 'set ' + info.n + " 1", {});
                }
            }
        }
        final_result.push({test: test.name, result: result});
        close(psid, ()=>{}, {});
    }
    callback(final_result);
};

module.exports.start = start;
module.exports.getPsid = getPsid;
module.exports.checkPsid = checkPsid;
module.exports.set = set;
module.exports.calc = calc;
module.exports.close = close;
module.exports.preset = preset;
module.exports.killAll = killAll;
module.exports.restart = restart;
module.exports.test = test;
