%% @doc The coordinator for stat write opeartions.  This example will
%% show how to properly replicate your data in Riak Core by making use
%% of the _preflist_.
-module(mfmn_write_fsm).
-behavior(gen_fsm).
-include("mfmn.hrl").

%% API
-export([start_link/5, start_link/6, write/3, write/4]).

%% Callbacks
-export([init/1, code_change/4, handle_event/3, handle_info/3,
         handle_sync_event/4, terminate/3]).

%% States
-export([prepare/2, execute/2, waiting/2]).

-record(state, {req_id :: pos_integer(),
                from :: pid(),
		key,
                val = undefined :: term() | undefined,
                preflist :: riak_core_apl:preflist2(),
                num_w = 0 :: non_neg_integer()}).

%%%===================================================================
%%% API
%%%===================================================================

%%start_link(ReqID, From) ->
%%    start_link(ReqID, From, undefined).

%%start_link(ReqID, From, Val) ->
%%    gen_fsm:start_link(?MODULE, [ReqID, From, Val], []).

write(Key) ->
    write(Key, undefined).

write(Key, Val) ->
    ReqID = mk_reqid(),
    mfmn_write_fsm_sup:start_write_fsm([ReqID, self(), Key, Val]),
    {ok, ReqID}.

%%%===================================================================
%%% States
%%%===================================================================

%% @doc Initialize the state data.
init([ReqID, From, Key, Val]) ->
    SD = #state{req_id=ReqID,
                from=From,
                key=Key,
                val=Val},
    {ok, prepare, SD, 0}.

%% @doc Prepare the write by calculating the _preference list_.
prepare(timeout, SD0=#state{client=Client,
                            stat_name=StatName}) ->
    DocIdx = riak_core_util:chash_key({list_to_binary(Client),
                                       list_to_binary(StatName)}),
    Preflist = riak_core_apl:get_apl(DocIdx, ?N, mfmn_stat),
    SD = SD0#state{preflist=Preflist},
    {next_state, execute, SD, 0}.

%% @doc Execute the write request and then go into waiting state to
%% verify it has meets consistency requirements.
execute(timeout, SD0=#state{req_id=ReqID,
                            stat_name=StatName,
                            op=Op,
                            val=Val,
                            preflist=Preflist}) ->
    case Val of
        undefined ->
            mfmn_stat_vnode:Op(Preflist, ReqID, StatName);
        _ ->
            mfmn_stat_vnode:Op(Preflist, ReqID, StatName, Val)
    end,
    {next_state, waiting, SD0}.

%% @doc Wait for W write reqs to respond.
waiting({ok, ReqID}, SD0=#state{from=From, num_w=NumW0}) ->
    NumW = NumW0 + 1,
    SD = SD0#state{num_w=NumW},
    if
        NumW =:= ?W ->
            From ! {ReqID, ok},
            {stop, normal, SD};
        true -> {next_state, waiting, SD}
    end.

handle_info(_Info, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_event(_Event, _StateName, StateData) ->
    {stop,badmsg,StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
    {stop,badmsg,StateData}.

code_change(_OldVsn, StateName, State, _Extra) -> {ok, StateName, State}.

terminate(_Reason, _SN, _SD) ->
    ok.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

mk_reqid() -> erlang:phash2(erlang:now()).
