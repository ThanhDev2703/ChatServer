%% @author thanhvu
%% @doc @todo Add description to cs_decode.


-module(cs_decode).
-include("cs.hrl").
%% ====================================================================
%% API functions
%% ====================================================================
-export([decode/1]).



%% ====================================================================
%% Internal functions
%% ====================================================================


decode(<<Len:16,Packet/binary>>) ->
	<<Bin:Len/binary,_/binary>> = Packet,
	JsonMap = jsx:decode(Bin, [return_maps]),
	
	Group = maps:get(<<"group">>, JsonMap),
	Type = maps:get(<<"type">>, JsonMap),
	Req_id = maps:get(<<"req_id">>, JsonMap),
	Data = maps:get(<<"data">>, JsonMap),
	
	io:format("data req ~p~n",[Data]),

	R = #request{group = Group, type = Type, req_id = Req_id, data = decode_data(Group,Type,Data)},
	io:format("Decode ~p~n",[R]),
	R.

decode_data(?GROUP_USER, ?TYPE_LOGIN, Data) ->
	Username = maps:get(<<"username">>, Data),
	Password = maps:get(<<"password">>, Data),
	#cmd_login{username = Username, password = Password};
decode_data(?GROUP_USER, ?TYPE_REGISTER, Data) ->
	Username = maps:get(<<"username">>, Data),
	Password = maps:get(<<"password">>, Data),
	FullName = maps:get(<<"fullname">>, Data),
	Email = maps:get(<<"phone">>, Data),
	Phone = maps:get(<<"email">>, Data),
	#cmd_register{username = Username,
				  password = Password,
				  fullname = FullName,
				  email = Email,
				  phone = Phone}; 
decode_data(?GROUP_USER, ?TYPE_USER_INFO, Data) ->
	UserName = maps:get(<<"username">>, Data),
	Token = maps:get(<<"token">>, Data),
	#cmd_user_info{username = UserName, token = Token};
decode_data(?GROUP_USER, ?TYPE_ME_INFO, Data) ->
	Token = maps:get(<<"token">>, Data),
	#cmd_me_info{token = Token};
decode_data(?GROUP_USER, ?TYPE_USER_AUTH, Data) ->
	Token = maps:get(<<"token">>, Data),
	#cmd_user_auth{token = Token};
decode_data(?GROUP_USER, ?TYPE_UPDATE_AVATAR, Data) ->
	Token = maps:get(<<"token">>, Data),
	Avatar = maps:get(<<"avatar">>, Data), 
	#cmd_update_avatar{token = Token, avatar = Avatar}; 
decode_data(?GROUP_USER, ?TYPE_UPDATE_DEVICE_TOKEN, Data) ->
	Token = maps:get(<<"token">>, Data),
	DT = maps:get(<<"device_token">>, Data),
	#cmd_update_device_token{token = Token, device_token = DT};
decode_data(?GROUP_USER, ?TYPE_SEARCH_USER, Data) ->
	Token = maps:get(<<"token">>, Data),
	Keyword = maps:get(<<"keyword">>, Data),
	Page = maps:get(<<"page">>, Data),
	#cmd_search_user{token = Token, keyword = Keyword, page = Page};
decode_data(?GROUP_CHAT, ?TYPE_SEND_MESSAGE, Data) ->
	Token = maps:get(<<"token">>, Data),
	ToUserName = maps:get(<<"to_user_name">>, Data),
	Message = maps:get(<<"message">>, Data),
	#cmd_send_message{token = Token, to_user_name = ToUserName, message = Message};
decode_data(?GROUP_CHAT, ?TYPE_CONFIRM_RECEIVED_MESSAGE, Data) ->
	MessageId = maps:get(<<"message_id">>, Data),
	Token = maps:get(<<"token">>, Data),
	#cmd_confirm_received_message{message_id = MessageId, token = Token};
decode_data(?GROUP_CHAT, ?TYPE_CONFIRM_RECEIVED_OFFLINE_MESSAGE, Data) ->
	Token = maps:get(<<"token">>, Data),
	#cmd_confirm_received_offline_message{token = Token};
decode_data(?GROUP_FRIEND, ?TYPE_ADD_FRIEND, Data) ->
	Token = maps:get(<<"token">>, Data),
	ToUser = maps:get(<<"to_user">>, Data),
	#cmd_add_friend{token = Token, to_user = ToUser};
decode_data(?GROUP_FRIEND, ?TYPE_ACCEPT_FRIEND_REQUEST, Data) ->
	Token = maps:get(<<"token">>, Data),
	FromUser = maps:get(<<"from_user">>, Data),
	#cmd_accept_friend_request{token = Token, from_user = FromUser};
decode_data(?GROUP_FRIEND, ?TYPE_REJECT_FRIEND_REQUEST, Data) ->
	Token = maps:get(<<"token">>, Data),
	FromUser = maps:get(<<"from_user">>, Data),
	#cmd_reject_friend_request{token = Token, from_user = FromUser};
decode_data(?GROUP_FRIEND, ?TYPE_GET_LIST_FRIEND, Data) ->
	Token = maps:get(<<"token">>, Data),
	Page = maps:get(<<"page">>, Data),
	#cmd_get_list_friend{token = Token, page = Page}; 
decode_data(?GROUP_FRIEND, ?TYPE_GET_LIST_FRIEND_REQUEST, Data) ->
	Token = maps:get(<<"token">>, Data),
	Page = maps:get(<<"page">>, Data),
	#cmd_get_list_friend_request{token = Token, page = Page};
decode_data(?GROUP_FRIEND, ?TYPE_UNFRIEND, Data) ->
	Token = maps:get(<<"token">>, Data),
	FriendUserName = maps:get(<<"friend_username">>, Data),
	#cmd_unfriend{token = Token, friend_username = FriendUserName};
decode_data(_Group, _Type, _Data) ->
	undefined.