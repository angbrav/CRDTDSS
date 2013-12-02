-module(mfmn).
-include("mfmn.hrl").
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
	 put/2,
	 get/1
        ]).

%% Public API

%% @doc Pings a random vnode to make sure communication is functional
ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(now())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, mfmn),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_spawn_command(IndexNode, ping, mfmn_vnode_master).

put(Key, Value)->
    {ok, ReqID} = rts_write_fsm:write(Client, StatName, Op),
    wait_for_reqid(ReqID, ?TIMEOUT).
    %%DocIdx = riak_core_util:chash_key({<<"key">>, term_to_binary(Key)}),
    %%PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, mfmn),
    %%[{IndexNode, _Type}] = PrefList,
    %%riak_core_vnode_master:sync_spawn_command(IndexNode, {put, Key, Value}, mfmn_vnode_master).

get(Key)->
    DocIdx = riak_core_util:chash_key({<<"key">>, term_to_binary(Key)}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, mfmn),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_spawn_command(IndexNode, {get, Key}, mfmn_vnode_master).
