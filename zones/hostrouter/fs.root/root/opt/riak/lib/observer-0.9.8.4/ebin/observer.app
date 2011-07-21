%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2002-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
{application, observer,
   [{description, "OBSERVER version 1"},
    {vsn, "0.9.8.4"},
    {modules, [crashdump_viewer,
	       crashdump_viewer_html,
	       etop,
	       etop_gui,
	       etop_tr,
	       etop_txt,
	       ttb,
	       ttb_et]},
    {registered, []},
    {applications, [kernel, stdlib]},
    {env, []}]}.


