%% @author thanhvu
%% @doc @todo Add description to cs_client.


-module(cs_client).
-behaviour(gen_fsm).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0,set_socket/2]).
-export([wait_for_socket/2,wait_for_data/2,change_state_online/3,auth/2]).


start_link() ->
	gen_fsm:start_link(?MODULE, [], []).
%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {socket,username,token}).
-include("cs.hrl").

set_socket(Socket, Pid) when is_pid(Pid), is_port(Socket) ->
	gen_fsm:send_event(Pid, {socket_ready, Socket}).

change_state_online(UserName,Token,Pid) when is_pid(Pid) ->
	Pid ! {change_state_online,UserName,Token}.

% check token expire after 60day
check_token_expire(_Token = #tbl_token{create_date = CreateDate}) ->
	Current = util:get_time_stamp_integer(erlang:timestamp()),
	Create = util:get_time_stamp_integer(CreateDate),
	if
		Current - 5184000 > Create ->
			true;
		true -> false
	end.

auth(TokenString,Pid) ->
	case cs_token_db:get_token(TokenString) of
		#db_res{result = Token = #tbl_token{uid = Uid}} ->
			case check_token_expire(Token) of
				true -> {error, token_expire};
				_ -> 
					case cs_user_db:user_info(Uid) of
						#db_res{result = #tbl_users{username = UserName}} ->
							cs_client_manager:add_client(UserName, TokenString, Pid),
							ok
					end
			end;
		_ -> {error, token_not_exist}
	end.
%% init/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:init-1">gen_fsm:init/1</a>
-spec init(Args :: term()) -> Result when
	Result :: {ok, StateName, StateData}
			| {ok, StateName, StateData, Timeout}
			| {ok, StateName, StateData, hibernate}
			| {stop, Reason}
			| ignore,
	StateName :: atom(),
	StateData :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
init([]) ->
    {ok, wait_for_socket, #state{}}.


wait_for_socket({socket_ready, Socket}, _StateData) ->
	inet:setopts(Socket, [{active, once}]),
	{next_state, wait_for_data, #state{socket = Socket}};
wait_for_socket(_Event,StateData) ->
	{next_state, wait_for_socket, StateData}.

wait_for_data({data, Packet}, #state{socket = Socket} = StateData) ->
	%lager:debug("Received data ~p~n", [Packet]),
	cs_process_data:process_data(Packet, Socket),
	{next_state, wait_for_data, StateData};
wait_for_data(_Event, StateData) ->
	{next_state, wait_for_data, StateData}.

%% handle_event/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_event-3">gen_fsm:handle_event/3</a>
-spec handle_event(Event :: term(), StateName :: atom(), StateData :: term()) -> Result when
	Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
	NextStateName :: atom(),
	NewStateData :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
handle_event(Event, StateName, StateData) ->
    {next_state, StateName, StateData}.


%% handle_sync_event/4
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_sync_event-4">gen_fsm:handle_sync_event/4</a>
-spec handle_sync_event(Event :: term(), From :: {pid(), Tag :: term()}, StateName :: atom(), StateData :: term()) -> Result when
	Result :: {reply, Reply, NextStateName, NewStateData}
			| {reply, Reply, NextStateName, NewStateData, Timeout}
			| {reply, Reply, NextStateName, NewStateData, hibernate}
			| {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, Reply, NewStateData}
			| {stop, Reason, NewStateData},
	Reply :: term(),
	NextStateName :: atom(),
	NewStateData :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
handle_sync_event(Event, From, StateName, StateData) ->
    Reply = ok,
    {reply, Reply, StateName, StateData}.


%% handle_info/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_info-3">gen_fsm:handle_info/3</a>
-spec handle_info(Info :: term(), StateName :: atom(), StateData :: term()) -> Result when
	Result :: {next_state, NextStateName, NewStateData}
			| {next_state, NextStateName, NewStateData, Timeout}
			| {next_state, NextStateName, NewStateData, hibernate}
			| {stop, Reason, NewStateData},
	NextStateName :: atom(),
	NewStateData :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: normal | term().
%% ====================================================================


handle_info({tcp, Socket, Packet}, StateName, StateData) ->
	inet:setopts(Socket, [{active, once}]),
	?MODULE:StateName({data, Packet}, StateData);
handle_info({tcp_closed, Socket}, _StateName, StateData = #state{username = UserName}) ->
	lager:debug("Client disconnected at ~p~n",[Socket]),
	cs_client_manager:remove_client(UserName),
    {stop, normal, StateData};
handle_info({change_state_online,UserName,Token}, StateName,StateData) ->
	NewState = StateData#state{username = UserName, token = Token},
	{next_state, StateName, NewState};
handle_info(Info, StateName, StateData) ->
	lager:debug("Unknow message ~p from StateName: ~p~n", [Info, StateName]),
    {next_state, StateName, StateData}.


%% terminate/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:terminate-3">gen_fsm:terminate/3</a>
-spec terminate(Reason, StateName :: atom(), StateData :: term()) -> Result :: term() when
	Reason :: normal
			| shutdown
			| {shutdown, term()}
			| term().
%% ====================================================================
terminate(Reason, StateName, StatData) ->
    ok.


%% code_change/4
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:code_change-4">gen_fsm:code_change/4</a>
-spec code_change(OldVsn, StateName :: atom(), StateData :: term(), Extra :: term()) -> {ok, NextStateName :: atom(), NewStateData :: term()} when
	OldVsn :: Vsn | {down, Vsn},
	Vsn :: term().
%% ====================================================================
code_change(OldVsn, StateName, StateData, Extra) ->
    {ok, StateName, StateData}.


%% ====================================================================
%% Internal functions
%% ====================================================================


