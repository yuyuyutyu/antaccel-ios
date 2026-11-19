var nativeObjectJs = {};
nativeObjectJs.os = {};
nativeObjectJs.os.isIOS = /iOS|iPhone|iPod/i.test(navigator.userAgent);
nativeObjectJs.os.isAndroid = /android/i.test(navigator.userAgent);
nativeObjectJs.callbacks = {};

//原生方法回调到js方法
nativeObjectJs.callback = function(params) {
    //从原生回调回来的参数获取callback的key
    var callbackKey = params.callback
    if(callbackKey !== undefined) {
        //从对象中取出callback回调
        var callback = nativeObjectJs.callbacks[callbackKey];
        if(callback !== undefined) {
            if(callback.callback !== undefined) {
                var args = params.args;
                var ret = callback.callback(args);
                if(ret === false) {
                    return
                }
                //删除回调
                delete nativeObjectJs.callbacks[callbackKey];
            }
        }
    }
};

//判断版本号
function compareVersion(oldVersion) {
    var userAgent = navigator.userAgent;
    var index = userAgent.indexOf("Android")
    if(index >= 0) {
        var androidVersion = parseFloat(userAgent.slice(index+8))
        if(androidVersion < oldVersion) {
            return true
        }
    }
    return false
}

//调用原生代码，不需要回调
nativeObjectJs.post = function(cmd, para) {
    if(window.nativeObjectJs.os.isAndroid) {
        var request = {};
        request.command = cmd;
        request.args = para;
        var jsonRequest = JSON.stringify(request);
        if(compareVersion(4.2)) {
            return prompt(jsonRequest, "jsCallJava")
        } else {
            window.nativeObject.postWithCallback(jsonRequest);
        }
    } else {
        var request = {};
        request.command = cmd;
        request.args = para;
        window.webkit.messageHandlers.nativeObject.postWithCallback(JSON.stringify(request))
    }
};

//调用原生代码，需要回调
nativeObjectJs.postWithCallback = function(cmd, para, callback) {
    //生成一个随机的key
    var callbackKey = "callBack_" + (new Date()).getTime() + "_key";
    //先去删除集合中相同的key的callback
    delete nativeObjectJs.callbacks[callbackKey];
    //将该callback回调缓存起来
    nativeObjectJs.callbacks[callbackKey] = {callback:callback};
    //判断是android还是ios
    if(window.nativeObjectJs.os.isAndroid) {
        var request = {};
        request.command = cmd;
        request.args = para;
        request.callback = callbackKey;
        var jsonRequest = JSON.stringify(request);
        if(compareVersion(4.2)) {
            return prompt(jsonRequest, "jsCallJava")
        } else {
            window.nativeObject.postWithCallback(jsonRequest);
        }
    } else {
        var request = {};
        request.command = cmd;
        request.args = para;
        request.callback = callbackKey;
        window.webkit.messageHandlers.nativeObject.postWithCallback(JSON.stringify(request))
    }
};

window.nativeObjectJs = nativeObjectJs;