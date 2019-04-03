# forkexec: sane child process library

This library provides somewhat saner interfaces to Node's
[child_process](https://nodejs.org/api/child_process.html) module.  It's still
growing, and most of the interfaces there don't have analogs here yet.

The interfaces in this library conform to Joyent's [Best Practices for Error
Handling in Node.js](http://www.joyent.com/developers/node/design/errors).  Most
notably:

* most arguments are passed via named properties of an "args" object, and
* passing invalid arguments into the library results in thrown exceptions that
  _should not be caught_.  Don't pass bad values in.

The only interfaces currently provided are:

* [forkExecWait](#forkexecwait)`(args, callback)`: like
  `child_process.execFile`, but all operational errors are emitted
  asynchronously, errors are more descriptive, and there's a crisper summary of
  exactly what happened.
* [interpretChildProcessResult](#interpretchildprocessresult)`(args)`:
  lower-level function for taking the result of one of Node's `child_process`
  functions and producing a normalized summary of what happened.

**One of the biggest challenges in using Node's child\_process interfaces is
properly interpreting the result.**  When you kick off a child process (as with
fork/exec), there are basically four possible outcomes:

1. Node failed to fork or exec the child process at all.
   (`error` is non-null, `status` is null, and `signal` is null)
2. The child process was successfully forked and exec'd, but terminated
   abnormally due to a signal.
   (`error` is non-null, `status` is null, and `signal` is non-null)
3. The child process was successfully forked and exec'd and exited
   with a status code other than 0.
   (`error` is non-null, `status` is a non-zero integer, and `signal` is null).
4. The child process was successfully forked and exec'd and exited with
   a status code of 0.
   (`error` is null, `status` is 0, and `signal` is null.)

Most code doesn't handle (1) at all, since it usually results in the
child\_process function throwing an exception rather than calling your callback.
Most use-cases want to treat (1), (2), and (3) as failure cases and generate a
descriptive error for them, but the built-in Errors are not very descriptive.

The interfaces here attempt to make the common case very easy (providing a
descriptive, non-null Error in cases (1) through (3), but not (4)), while still
allowing more complex callers to easily determine exactly what happened.  These
interfaces do this by taking the result of the underlying Node API function and
producing an `info` object with properties:

* **error**: null if the child process was created and terminated normally with
  exit\_status 0.  This is a non-null, descriptive error if the child process was
  not created at all, if the process was terminated abnormally by a signal, or
  if the process was terminated normally with a non-zero exit status.
* **status**: the wait(2) numeric status code if the child process exited
  normally, and null otherwise.
* **signal**: the name of the signal that terminated the child process if the
* child process exited abnormally as a result of a signal, or null otherwise


## forkExecWait

Like the built-in `child_process.execFile`, this function forks a child process,
exec's the requested command, waits for it to exit, and captures the full stdout
and stderr.  The file should be an executable on the caller's PATH.  It is
_not_ passed through `bash -c` as would happen with `child_process.exec`.

### Arguments

```javascript
forkExecWait(args, callback)
```

The main argument is:

* **argv** (array of string): command-line arguments, _including the command
  name itself_.  If you want to run "ls -l", this should be `[ 'ls', '-l' ]`.

The following arguments have the same semantics as for Node's built-in
`child_process.execFile` except where otherwise noted:

* **timeout** (int: milliseconds): maximum time the child process may run before
  SIGKILL will be sent to it.  If 0, then there is no timeout.  (Note that Node
  lets you override the signal used and defaults to SIGTERM.  This interface
  always uses SIGKILL.)
* **cwd** (string): working directory
* **encoding** (string): encoding for stdout and stderr
* **env** (object): environment variables
* **maxBuffer** (int): bytes of stdout and stderr that will be buffered
* **uid** (int): uid for child process
* **gid** (int): gid for child process
* **includeStderr** (boolean): if the process exits with a non-zero status,
  the output of `stderr` will be trimmed and included in the error message.
  Defaults to `false`.

### Return value

The return value is the same as `child_process.execFile` except when that
function would throw an exception, in which case this function will return
`null` and the error that would have been thrown is instead emitted to the
callback (as you'd probably have expected Node to do).

### Callback

The callback is invoked as `callback(err, info)`, where `info` always has
properties:

* **error**, **status**, **signal**: see description of "info" object above.
  `info.error` is the same as the `err` argument.
* **stdout**: the string contents of the command's stdout.  This is unspecified
  if the process was not successfully exec'd.
* **stderr**: the string contents of the command's stderr.  This is unspecified
  if the process was not successfully exec'd.

### Error handling

As described above, the interface throws on programmer errors, and these should
not be handled.  Operational errors are emitted asynchronously.  See the four
possible outcomes described above for what those are.

### Examples

Normal command:

```javascript
forkExecWait({
    'argv': [ 'echo', 'hello', 'world' ]
}, function (err, info) {
    console.log(info);
});
```

```javascript
{ error: null,
  status: 0,
  signal: null,
  stdout: 'hello world\n',
  stderr: '' }
```

Successful fork/exec, command fails:

```javascript
forkExecWait({
    'argv': [ 'grep', 'foobar' '/nonexistent_file' ]
}, function (err, info) {
    console.log(info);
});
```

```javascript
{ error: 
   { [VError: exec "grep foobar /nonexistent_file": exited with status 2]
     jse_shortmsg: 'exec "grep foobar /nonexistent_file"',
     jse_summary: 'exec "grep foobar /nonexistent_file": exited with status 2',
     jse_cause: 
      { [VError: exited with status 2]
        jse_shortmsg: 'exited with status 2',
        jse_summary: 'exited with status 2',
        message: 'exited with status 2' },
     message: 'exec "grep foobar /nonexistent_file": exited with status 2' },
  status: 2,
  signal: null,
  stdout: '',
  stderr: 'grep: /nonexistent_file: No such file or directory\n' }
```

Failed fork/exec: command not found:

```javascript
forkExecWait({
    'argv': [ 'nonexistent', 'command' ]
}, function (err, info) {
    console.log(info);
});
```

```javascript
{ error: 
   { [VError: exec "nonexistent command": spawn nonexistent ENOENT]
     jse_shortmsg: 'exec "nonexistent command"',
     jse_summary: 'exec "nonexistent command": spawn nonexistent ENOENT',
     jse_cause: 
      { [Error: spawn nonexistent ENOENT]
        code: 'ENOENT',
        errno: 'ENOENT',
        syscall: 'spawn nonexistent',
        path: 'nonexistent',
        cmd: 'nonexistent command' },
     message: 'exec "nonexistent command": spawn nonexistent ENOENT' },
  status: null,
  signal: null,
  stdout: '',
  stderr: '' }
```

Failed fork/exec: command is not executable (note: Node throws on this, while
this library emits an error asynchronously, since this is an operational error):

```javascript
forkExecWait({
    'argv': [ '/dev/null' ]
}, function (err, info) {
    console.log(info);
});
```

```javascript
{ error: 
   { [VError: exec "/dev/null": spawn EACCES]
     jse_shortmsg: 'exec "/dev/null"',
     jse_summary: 'exec "/dev/null": spawn EACCES',
     jse_cause: { [Error: spawn EACCES] code: 'EACCES', errno: 'EACCES', syscall: 'spawn' },
     message: 'exec "/dev/null": spawn EACCES' },
  status: null,
  signal: null,
  stdout: '',
  stderr: '' }
```

Command times out (killed by our SIGKILL after 3 seconds):

```javascript
forkExecWait({
    'argv': [ 'sleep', '4' ],
    'timeout': 3000,
}, function (err, info) {
    console.log(info);
});
```

```javascript
{ error: 
   { [VError: exec "sleep 2": unexpectedly terminated by signal SIGKILL]
     jse_shortmsg: 'exec "sleep 2"',
     jse_summary: 'exec "sleep 2": unexpectedly terminated by signal SIGKILL',
     jse_cause: 
      { [VError: unexpectedly terminated by signal SIGKILL]
        jse_shortmsg: 'unexpectedly terminated by signal SIGKILL',
        jse_summary: 'unexpectedly terminated by signal SIGKILL',
        message: 'unexpectedly terminated by signal SIGKILL' },
     message: 'exec "sleep 2": unexpectedly terminated by signal SIGKILL' },
  status: null,
  signal: 'SIGKILL',
  stdout: '',
  stderr: '' }
```


## interpretChildProcessResult

This lower-level function takes the results of one of the `child_process`
functions and produces the `info` object described above, including a more
descriptive Error (if there was one).

### Arguments

```javascript
interpretChildProcessResult(args)
```

Named arguments are:

* **label** (string): label for the child process.  This can be just the command
  (e.g., "grep"), the full argument string (e.g., "grep foo /my/files"), a
  human-readable label (e.g., "grep subprocess"), or whatever else you want to
  report with an optional error.
* **error** (optional Error): error object reported by one of Node's
  child_process functions.  Per the Node docs, this should be either `null` or
  an instance of Error.

### Return value

The return value is an `info` object with the `error`, `status`, and `signal`
properties described above.


### Error handling

As described above, the interface throws on programmer errors, and these should
not be handled.  There are no operational errors for this interface.


# Contributions

Contributions welcome.  Code should be "make prepush" clean.  To run "make
prepush", you'll need these tools:

* https://github.com/davepacheco/jsstyle
* https://github.com/davepacheco/javascriptlint

If you're changing something non-trivial or user-facing, you may want to submit
an issue first.
