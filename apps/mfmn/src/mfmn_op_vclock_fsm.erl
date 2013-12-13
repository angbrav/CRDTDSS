%% @doc The coordinator for stat write opeartions.  This example will
%% show how to properly replicate your data in Riak Core by making use
%% of the _preflist_.
-module(mfmn_op_vclock_fsm).
-behavior(gen_fsm).
-include("mfmn.hrl").

%% API
-export([start_link/5]).

%% Callbacks
-export([init/1, code_change/4, handle_event/3, handle_info/3,
         handle_sync_event/4, terminate/3]).

%% States
-export([prepare/2, execute/2, waiting/2]).

-record(state, {req_id :: pos_integer(),
                from :: pid(),
		coordinator :: node(),
		op :: atom(),
		vclock,
		key,
                preflist :: riak_core_apl:preflist2(),
                num_r = 0 :: non_neg_integer()}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(ReqID, From, Op, Vclock, Key) ->
    gen_fsm:start_link(?MODULE, [ReqID, From, Op, Vclock, Key], []).

%%%===================================================================
%%% States
%%%===================================================================

%% @doc Initialize the state data.
init([ReqID, From, Op, Vclock, Key]) ->
    SD = #state{req_id=ReqID,
                from=From,
		coordinator=node(),
		op=Op,
		vclock=Vclock,
                key=Key},
    {ok, prepare, SD, 0}.

%% @doc Prepare the write by calculating the _preference list_.
prepare(timeout, SD0=#state{key=Key}) ->
    DocIdx = riak_core_util:chash_key({<<"basic">>,
                                       term_to_binary(Key)}),
    Preflist = riak_core_apl:get_apl(DocIdx, ?N, mfmn),
    SD = SD0#state{preflist=Preflist},
    {next_state, execute, SD, 0}.

%% @doc Execute the write request and then go into waiting state to
%% verify it has meets consistency requirements.
execute(timeout, SD0=#state{req_id=ReqID,
			    coordinator=Coordinator,
                            op=Op,
			    vclock=Vclock,
			    key=Key,
                            preflist=Preflist}) ->
    mfmn_vnode:Op(Preflist, {ReqID, Coordinator}, Vclock, Key),
    {next_state, waiting, SD0}.

%% @doc Waits for 1 write reqs to respond.
waiting({ReqID, Val, Lease}, SD0=#state{from=From, key=Key}) ->
    %SD = SD0#state{val=Val},
    mfmn_cache:add_key(From, ReqID, Key, Val, Lease),
    {stop, normal, SD0};

waiting({error, no_updated}, SD=#state{num_r=R}) ->
    NewR = R + 1,
    if NewR == ?N ->
        {stop, normal, SD#state{num_r=NewR}};
    true ->
        {next_state, waiting, SD#state{num_r=NewR}}
    end;

waiting({error, no_key}, SD=#state{num_r=R}) ->
    NewR = R + 1,
    if NewR == ?N ->
        {stop, normal, SD#state{num_r=NewR}};
    true ->
        {next_state, waiting, SD#state{num_r=NewR}}
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
