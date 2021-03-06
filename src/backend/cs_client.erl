%% @author thanhvu
%% @doc @todo Add description to cs_client.


-module(cs_client).
-behaviour(gen_fsm).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0,set_socket/2,received_data/2]).
-export([wait_for_socket/2,wait_for_auth/2,wait_for_data/2,change_state_online/4,auth/2,check_token/2,received_message/2]).
-export([received_friend_request/2,send_data_res/2]).

start_link() ->
	gen_fsm:start_link(?MODULE, [], []).
%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {socket,username,token, fullname}).
-include("cs.hrl").

set_socket(Socket, Pid) when is_pid(Pid), is_port(Socket) ->
	gen_fsm:send_event(Pid, {socket_ready, Socket}).

change_state_online(UserName,FullName,Token,Pid) when is_pid(Pid) ->
	%Pid ! {change_state_online,UserName,Token}.
	gen_fsm:send_event(Pid, {auth_success, UserName,FullName, Token}).

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
		#db_res{result = Token = #tbl_token{username = UserName}} ->
			case check_token_expire(Token) of
				true -> {error, token_expire};
				_ -> 
					case cs_user_db:user_info(UserName) of
						#db_res{error = ?DB_DONE, result = #tbl_users{fullname = FullName}} ->
							cs_client_manager:add_client(UserName,FullName, TokenString, Pid),
							ok;
						_ -> ok
					end
			end;
		_ -> {error, token_not_exist}
	end.

check_token(TokenString, StateData) ->
	#state{token = Token, username = UserName, fullname = FullName} = StateData,
	if
		Token == TokenString ->
			{ok, UserName, FullName};
		true -> {error, token_fail}
	end.

received_message(Pid, Binary) ->
	gen_fsm:send_event(Pid, {received_message, Binary}).

received_friend_request(Pid, Binary) ->
	gen_fsm:send_event(Pid, {received_friend_request, Binary}).

received_data(Pid, Binary) ->
	gen_fsm:send_event(Pid, {received_data, Binary}).

send_data_res(Pid, Obj) ->
	gen_fsm:send_event(Pid, {send_data, Obj}).
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
	{next_state, wait_for_auth, #state{socket = Socket}};
wait_for_socket(_Event,StateData) ->
	{next_state, wait_for_socket, StateData}.

% wait_for_data - after auth
wait_for_data({data, Packet}, #state{socket = Socket} = StateData) ->
	%lager:debug("Received data ~p~n", [Packet]),
	cs_process_data:process_data(Packet, Socket,StateData),
	{next_state, wait_for_data, StateData};
wait_for_data({received_message, Binary}, StateData = #state{socket = Socket}) ->
	gen_tcp:send(Socket, Binary),
	{next_state, wait_for_data, StateData};
wait_for_data({received_friend_request, Binary}, StateData = #state{socket = Socket}) ->
	gen_tcp:send(Socket, Binary),
	{next_state, wait_for_data, StateData};
wait_for_data({received_data, Binary}, StateData = #state{socket = Socket}) ->
	gen_tcp:send(Socket, Binary),
	{next_state, wait_for_data, StateData};
wait_for_data({send_data, Obj}, StateData = #state{socket = Socket}) ->
	ResponseBin = cs_encode:encode(Obj),	
	Len = byte_size(ResponseBin),
	gen_tcp:send(Socket, <<Len:16,ResponseBin/binary>>),
	{next_state, wait_for_data, StateData};
wait_for_data(_Event, StateData) ->
	{next_state, wait_for_data, StateData}.

% wait_for_auth
wait_for_auth({data, Packet}, #state{socket = Socket} = StateData) ->
	cs_process_data:process_data(Packet, Socket,StateData),
	{next_state, wait_for_auth, StateData};
wait_for_auth({auth_success, UserName,FullName, Token}, StateData = #state{socket = Socket}) ->
	NewState = StateData#state{username = UserName, token = Token, fullname = FullName},
	lager:info("Auth success with UserName: ~p, Token: ~p~n", [UserName, Token]),
	% get offline message
	cs_process_message:send_message_offline(UserName, Socket),
	{next_state, wait_for_data, NewState};
wait_for_auth(_Event, StateData) ->
	{next_state, wait_for_auth, StateData}.


handle_event(_Event, StateName, StateData) ->
	{next_state, StateName, StateData}.



handle_sync_event(_Event, _From, StateName, StateData) ->
	Reply = ok,
	{reply, Reply, StateName, StateData}.


handle_info({tcp, Socket, Packet}, StateName, StateData) ->
	inet:setopts(Socket, [{active, once}]),
	?MODULE:StateName({data, Packet}, StateData);
	handle_info({tcp_closed, _Socket}, _StateName, StateData = #state{username = _UserName}) ->
	%lager:debug("Client disconnected at ~p~n",[Socket]),
	%cs_client_manager:remove_client(UserName, self()),
	{stop, normal, StateData};
handle_info({kill}, _StateName, StateData = #state{socket = Socket}) ->
	Obj = #response{group = ?GROUP_USER,
					type = ?TYPE_KICK_ANOTHER_LOGIN,
					req_id = 0,
					result = 0,
					data = undefined},
	ResponseBin = cs_encode:encode(Obj),
	Len = byte_size(ResponseBin),
	gen_tcp:send(Socket, <<Len:16,ResponseBin/binary>>),
	gen_tcp:close(Socket),
	{stop, normal, StateData};
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
terminate(_Reason, _StateName, _StateData = #state{username = UserName, socket = Socket}) ->
	lager:debug("Client disconnected at ~p~n",[Socket]),
	case UserName of
		undefined -> ok;
		_ ->
			cs_client_manager:remove_client(UserName),
			cs_process_friend:notice_friend_offline(UserName)
	end,
	gen_tcp:close(Socket),
ok.


%% code_change/4
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_fsm.html#Module:code_change-4">gen_fsm:code_change/4</a>
-spec code_change(OldVsn, StateName :: atom(), StateData :: term(), Extra :: term()) -> {ok, NextStateName :: atom(), NewStateData :: term()} when
OldVsn :: Vsn | {down, Vsn},
Vsn :: term().
%% ====================================================================
code_change(_OldVsn, StateName, StateData, _Extra) ->
{ok, StateName, StateData}.


%% ====================================================================
%% Internal functions
%% ====================================================================


