--[[

    Copyright (C) 2017 Masatoshi Teruya

    Permission is hereby granted, free of chvale, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to
    deal in the Software without restriction, including without limitation the
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.

    parser.lua
    lua-jsonrpc-parser

    Created by Masatoshi Teruya on 17/02/05.

--]]

--- modules
local encode = require('cjson.safe').encode;
local decode = require('cjson.safe').decode;
local type = type;
local floor = math.floor;
--- constants
local INFINITE_POS = math.huge;
local INFINITE_NEG = -INFINITE_POS;
local METHOD_PAT = '^[a-zA-Z_][a-zA-Z0-9_.]*$';
local IDENT_PAT = '^[a-zA-Z0-9_-.]+$';
-- -32700 Parse error
-- Invalid JSON was received by the server.
-- An error occurred on the server while parsing the JSON text.
local EPARSE = -32700;
-- -32600 Invalid Request
-- The JSON sent is not a valid Request object.
local EINVAL = -32600;
-- -32601 Method not found
-- The method does not exist / is not available.
local ENOENT = -32601;
-- -32602 Invalid params
-- Invalid method parameter(s).
local EPARAMS = -32602;
-- -32603 Internal error
-- Internal JSON-RPC error.
local EERROR = -32603;
-- -32000 to -32099 Server error
-- Reserved for implementation-defined server-errors.
local ERSVD_MIN = -32000;
local ERSVD_MAX = -32099;
--- default message
local DEFAULT_MESSAGE = {
    [EPARSE] = 'Invalid JSON was received',
    [EINVAL] = 'Invalid Request',
    [ENOENT] = 'Method not found',
    [EPARAMS] = 'Invalid params',
    [EERROR] = 'Internal JSON-RPC error'
};


--- isFinite
-- @param val
-- @return ok
local function isFinite( val )
    return type( val ) == 'number' and
           ( val < INFINITE_POS and val > INFINITE_NEG );
end


-- @param val
-- @return ok
local function isInt( val )
    return isFinite( val ) and floor( val ) == val;
end


--- verifyIdent
-- @param id
-- @return ok
local function verifyIdent( id )
    return isInt( id ) or type( id ) == 'string' and id:find( IDENT_PAT );
end


--- verifyError
-- @param err
-- @param id
-- @return ok
local function verifyError( err, id )
    if type( err ) == 'table' and
       ( err.message == nil or type( err.message ) == 'string' ) and
       isInt( err.code ) then
        -- If there was an error in detecting the id in the Request object
        -- (e.g. Parse error/Invalid Request), it MUST be Null
        if err.code == EPARSE or err.code == EINVAL then
            return id == nil;
        end

        return (( err.code > EINVAL and err.code <= EERROR ) or
                ( err.code >= ERSVD_MIN and err.code <= ERSVD_MAX )) and
                verifyIdent( id );
    end

    return false;
end


--- verifyParams
-- @param params
-- @return ok
local function verifyParams( params )
    return params == nil or type( params ) == 'table';
end


--- verifyMethod
-- @param method
-- @return ok
local function verifyMethod( method )
    return type( method ) == 'string' and method:find( METHOD_PAT ) and
           true or false;
end


--- verifyVersion
-- @param ver
-- @return ok
local function verifyVersion( ver )
    return type( ver ) == 'string' and ver == '2.0';
end


--- verifyResponse
-- @param json
-- @param ok
local function verifyResponse( json )
    if verifyVersion( json.jsonrpc ) then
        if json.error == nil then
            return json.result ~= nil;
        elseif json.result == nil then
            return verifyError( json.error, json.id );
        end
    end

    return false;
end


--- verifyRequest
-- @param json
-- @param ok
local function verifyRequest( json )
    return verifyVersion( json.jsonrpc ) and
           verifyMethod( json.method ) and
           verifyParams( json.params ) and
           ( json.id == nil or verifyIdent( json.id ) );
end


--- parseMessage
-- @param data
-- @return json
-- @return err
local function parseMessage( data, verifier )
    -- parse data as a JSON
    local json, err = decode( data );

    -- invalid json format
    if err then
        return nil, EPARSE;
    -- invalid json-rpc 2.0 format
    elseif type( json ) ~= 'table' then
        return nil, EINVAL;
    -- batch request/response
    elseif #json > 0 then
        for i = 1, #json do
            if not verifier( json[i] ) then
                return nil, EINVAL;
            end
        end
    -- single request/response
    elseif not verifier( json ) then
        return nil, EINVAL;
    end

    return json;
end


--- parseRequest
-- @param data
-- @return json
-- @return err
local function parseRequest( data )
    return parseMessage( data, verifyRequest );
end


--- parseResponse
-- @param data
-- @return json
-- @return err
local function parseResponse( data )
    return parseMessage( data, verifyResponse );
end


--- makeRequest
-- @param method
-- @param params
-- @param id
-- @return json
-- @return err
local function makeRequest( method, params, id )
    if not verifyMethod( method ) then
        return nil, 'method must be ' .. METHOD_PAT;
    elseif not verifyParams( params ) then
        return nil, 'params must be nil or table';
    elseif ( id ~= nil and verifyIdent( id ) ) then
        return nil, 'id must be nil, integer or string ' .. IDENT_PAT;
    end

    return encode({
        jsonrpc = "2.0",
        method = method,
        params = params,
        id = id
    });
end


--- makeResponse
-- @param res
-- @param id
-- @return json
-- @return err
local function makeResponse( res, id )
    if res == nil then
        return nil, 'res must be not nil';
    elseif not verifyIdent( id ) then
        return nil, 'id must be integer or string ' .. IDENT_PAT;
    end

    return encode({
        jsonrpc = "2.0",
        result = res,
        id = id
    });
end


--- makeError
-- @param code
-- @param msg
-- @param data
-- @param id
-- @return json
-- @return err
local function makeError( code, msg, data, id )
    if not isInt( code ) or
       not ( code == EPARSE or
            ( code <= EINVAL and code >= EERROR ) or
            ( code <= ERSVD_MIN and code >= ERSVD_MAX )) then
        return nil, 'code must be -32700, -32600 to -32603 or -32000 to -32099';
    elseif msg ~= nil and type( msg ) ~= 'string' then
        return nil, 'msg must be nil or string';
    -- If there was an error in detecting the id in the Request object
    -- (e.g. Parse error/Invalid Request), it MUST be Null
    elseif ( code == EPARSE or code == EINVAL ) then
        if id ~= nil then
            return nil, 'id must be nil if code equal to -32700 or -32600';
        end
    elseif not verifyIdent( id ) then
        return nil, 'id must be integer or string ' .. IDENT_PAT;
    end

    return encode({
        jsonrpc = "2.0",
        error = {
            code = code,
            message = msg or DEFAULT_MESSAGE[code],
            data = data
        },
        id = id
    });
end


return {
    --- constants
    -- -32700 Parse error
    -- Invalid JSON was received by the server.
    -- An error occurred on the server while parsing the JSON text.
    EPARSE = EPARSE,
    -- -32600 Invalid Request
    -- The JSON sent is not a valid Request object.
    EINVAL = EINVAL,
    -- -32601 Method not found
    -- The method does not exist / is not available.
    ENOENT = ENOENT,
    -- -32602 Invalid params
    -- Invalid method parameter(s).
    EPARAMS = EPARAMS,
    -- -32603 Internal error
    -- Internal JSON-RPC error.
    EERROR = EERROR,
    -- -32000 to -32099 Server error
    -- Reserved for implementation-defined server-errors.
    ERSVD_MIN = ERSVD_MIN,
    ERSVD_MAX = ERSVD_MAX,

    --- APIs
    parseRequest = parseRequest,
    parseResponse = parseResponse,
    makeRequest = makeRequest,
    makeResponse = makeResponse,
    makeError = makeError
};

