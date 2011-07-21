{application, basho_stats,
 [{description, "Basic Erlang statistics library"},
  {vsn, "1.0.1"},
  {modules, [ basho_stats_sample,
              basho_stats_histogram,
              basho_stats_rv,
              basho_stats_utils]},
  {registered, []},
  {applications, [kernel, 
                  stdlib, 
                  sasl]},
  {env, []}
]}.
