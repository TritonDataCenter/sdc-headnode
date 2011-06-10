/* Copyright Joyent, Inc. and other Node contributors.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to permit
 * persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
 * NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
 * USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/*
 * This is the DTrace library file for the node provider, which includes
 * the necessary translators to get from the args[] to something useful.
 * Be warned:  the mechanics here are seriously ugly -- and one must always
 * keep in mind that clean abstractions often require filthy systems.
 */
#pragma D depends_on library procfs.d

typedef struct {
	int32_t fd;
	int32_t port;
	uint32_t remote;
	uint32_t buffered;
} node_dtrace_connection_t;

typedef struct {
	int32_t fd;
	int32_t port;
	uint64_t remote;
	uint32_t buffered;
} node_dtrace_connection64_t;

typedef struct {
	int fd;
	string remoteAddress;
	int remotePort;
	int bufferSize;
} node_connection_t;

translator node_connection_t <node_dtrace_connection_t *nc> {
	fd = *(int32_t *)copyin((uintptr_t)&nc->fd, sizeof (int32_t));
	remotePort =
	    *(int32_t *)copyin((uintptr_t)&nc->port, sizeof (int32_t));
	remoteAddress = curpsinfo->pr_dmodel == PR_MODEL_ILP32 ?
	    copyinstr((uintptr_t)*(uint32_t *)copyin((uintptr_t)&nc->remote,
	    sizeof (int32_t))) :
	    copyinstr((uintptr_t)*(uint64_t *)copyin((uintptr_t)
	    &((node_dtrace_connection64_t *)nc)->remote, sizeof (int64_t)));
	bufferSize = curpsinfo->pr_dmodel == PR_MODEL_ILP32 ?
	    *(uint32_t *)copyin((uintptr_t)&nc->buffered, sizeof (int32_t)) :
	    *(uint32_t *)copyin((uintptr_t)
	    &((node_dtrace_connection64_t *)nc)->buffered, sizeof (int32_t));
};

typedef struct {
	uint32_t url;
	uint32_t method;
} node_dtrace_http_request_t;

typedef struct {
	uint64_t url;
	uint64_t method;
} node_dtrace_http_request64_t;

typedef struct {
	string url;
	string method;
} node_http_request_t;

translator node_http_request_t <node_dtrace_http_request_t *nd> {
	url = curpsinfo->pr_dmodel == PR_MODEL_ILP32 ?
	    copyinstr((uintptr_t)*(uint32_t *)copyin((uintptr_t)&nd->url,
	    sizeof (int32_t))) :
	    copyinstr((uintptr_t)*(uint64_t *)copyin((uintptr_t)
	    &((node_dtrace_http_request64_t *)nd)->url, sizeof (int64_t)));
	method = curpsinfo->pr_dmodel == PR_MODEL_ILP32 ?
	    copyinstr((uintptr_t)*(uint32_t *)copyin((uintptr_t)&nd->method,
	    sizeof (int32_t))) :
	    copyinstr((uintptr_t)*(uint64_t *)copyin((uintptr_t)
	    &((node_dtrace_http_request64_t *)nd)->method, sizeof (int64_t)));
};
