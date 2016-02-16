#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option switchrate=10hz
#pragma D option dynvarsize=16m
#pragma D option bufsize=8m

/* If AF_INET and AF_INET6 are "Unknown" to DTrace, replace with numbers: */
inline int af_inet = 2 /*AF_INET*/;
inline int af_inet6 = 28 /*AF_INET6*/;

BEGIN {
	printf("[\n");
	comma="";
}

END {
  printf("]\n");
}

syscall::open:entry
/pid != $pid/
{
	printf("%s {\"event\": \"%s:%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"path\": \"%s\"}\n",
	    comma, probefunc, probename, walltimestamp, pid, uid, execname, copyinstr(arg0));
	comma=",";
}

syscall::open:return
/pid != $pid/
{
	printf("%s {\"event\": \"%s:%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"fd\": \"%d\"}\n",
	    comma, probefunc, probename, walltimestamp, pid, uid, execname, arg0);
	comma=",";
}

syscall::openat:entry
/pid != $pid/
{
	printf("%s {\"event\": \"%s:%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"path\": \"%s\"}\n",
	    comma, probefunc, probename, walltimestamp, pid, uid, execname, copyinstr(arg1));
	comma=",";
}

syscall::openat:return
/pid != $pid/
{
	printf("%s {\"event\": \"%s:%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"fd\": \"%d\"}\n",
	    comma, probefunc, probename, walltimestamp, pid, uid, execname, arg0);
	comma=",";
}

/* TODO: Add support for fds[arg0].fi_pathname */
syscall::read:entry,syscall::write:entry,
syscall::pread:entry,syscall::pwrite:entry,
syscall::readv:entry,syscall::writev:entry,
syscall::pread:entry,syscall::pwrite:entry,
syscall::preadv:entry,syscall::pwritev:entry
/pid != $pid && execname != "sshd" && execname != "tmux"/
{
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"fd\": %d}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname, arg0);
	comma=",";
}

syscall::execve:entry
/pid != $pid/
{
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"ppid\": %d, \"uid\": %d, \"exec\": \"%s\"}\n",
	    comma, probefunc, walltimestamp, pid, curpsinfo->pr_ppid, uid, copyinstr(arg0));
	comma=",";
}


syscall::fork:entry,syscall::rfork:entry,syscall::vfork:entry
/pid != $pid/
{
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\"}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname);
	comma=",";
}

syscall::exit:entry
/pid != $pid/
{
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\"}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname);
	comma=",";
}

syscall::connect*:entry
{
	/* assume this is sockaddr_in until we can examine family */
	this->s = (struct sockaddr_in *)copyin(arg1, sizeof (struct sockaddr));
	this->f = this->s->sin_family;
}

syscall::connect*:entry
/this->f == af_inet/
{
	self->family = this->f;
	self->port = ntohs(this->s->sin_port);
	self->address = inet_ntop(self->family, (void *)&this->s->sin_addr);
	self->start = timestamp;
}

syscall::connect*:entry
/this->f == af_inet6/
{
	/* refetch for sockaddr_in6 */
	this->s6 = (struct sockaddr_in6 *)copyin(arg1,
	    sizeof (struct sockaddr_in6));
	self->family = this->f;
	self->port = ntohs(this->s6->sin6_port);
	self->address = inet_ntoa6((in6_addr_t *)&this->s6->sin6_addr);
	self->start = timestamp;
}

syscall::connect*:return
/self->start/
{
	this->delta = (timestamp - self->start) / 1000;
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"family\": %d, \"address\": \"%s\", \"port\": %d, \"err\": %d}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname, self->family, self->address, self->port, errno);
	comma=",";
	self->family = 0;
	self->address = 0;
	self->port = 0;
	self->start = 0;
}

syscall::accept*:entry
{
	self->sa = arg1;
	self->start = timestamp;
}

syscall::accept*:return
/self->sa/
{
	this->delta = (timestamp - self->start) / 1000;
	/* assume this is sockaddr_in until we can examine family */
	this->s = (struct sockaddr_in *)copyin(self->sa,
	    sizeof (struct sockaddr_in));
	this->f = this->s->sin_family;
}

syscall::accept*:return
/this->f == af_inet/
{
	this->port = ntohs(this->s->sin_port);
	this->address = inet_ntoa((in_addr_t *)&this->s->sin_addr);
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"family\": %d, \"address\": \"%s\", \"port\": %d, \"err\": %d}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname, this->f, this->address, this->port, errno);
	comma=",";
}

syscall::accept*:return
/this->f == af_inet6/
{
	/* refetch for sockaddr_in6 */
	this->s6 = (struct sockaddr_in6 *)copyin(self->sa,
	    sizeof (struct sockaddr_in6));
	this->port = ntohs(this->s6->sin6_port);
	this->address = inet_ntoa6((in6_addr_t *)&this->s6->sin6_addr);
	printf("%s {\"event\": \"%s\", \"time\": %d, \"pid\": %d, \"uid\": %d, \"exec\": \"%s\", \"family\": %d, \"address\": \"%s\", \"port\": %d, \"err\": %d}\n",
	    comma, probefunc, walltimestamp, pid, uid, execname, this->f, this->address, this->port, errno);
	comma=",";
}

syscall::accept*:return
/self->start/
{
	self->sa = 0; self->start = 0;
}
