#ifdef __cplusplus
extern "C" {
#endif

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#include <embed.h>

#ifdef __cplusplus
} /* extern "C" */
#endif

#define NEED_newSVpvn_flags
#include "ppport.h"

#define HAVE_ACCEPT4

static OP* my_accept(pTHX) {
    dVAR; dSP; dTARGET;
    IO *nstio;
    IO *gstio;
    char namebuf[MAXPATHLEN];
#if (defined(VMS_DO_SOCKETS) && defined(DECCRTL_SOCKETS)) || defined(__QNXNTO__)
    Sock_size_t len = sizeof (struct sockaddr_in);
#else
    Sock_size_t len = sizeof namebuf;
#endif
    GV * const ggv = MUTABLE_GV(POPs);
    GV * const ngv = MUTABLE_GV(POPs);
    int fd;

    if (!ngv)
	goto badexit;
    if (!ggv)
	goto nuts;

    gstio = GvIO(ggv);
    if (!gstio || !IoIFP(gstio))
	goto nuts;

    nstio = GvIOn(ngv);
#if defined(HAVE_ACCEPT4) && defined(SOCK_CLOEXEC)
    /* accept4() is available on Linux 2.6.28+ and glibc 2.10 */
    static int accept4_works = -1;
#endif

#if defined(HAVE_ACCEPT4) && defined(SOCK_CLOEXEC)
    if (accept4_works != 0) {
        fd = accept4(PerlIO_fileno(IoIFP(gstio)), (struct sockaddr *) namebuf, &len, O_CLOEXEC);
        if (fd == -1 && accept4_works != -1) {
            /* On Linux older than 2.6.28, accept4() fails with ENOSYS */
            accept4_works = (errno != ENOSYS);
        }
    }
    if (accept4_works == 0)
        fd = PerlSock_accept(PerlIO_fileno(IoIFP(gstio)), (struct sockaddr *) namebuf, &len);
#else
    fd = PerlSock_accept(PerlIO_fileno(IoIFP(gstio)), (struct sockaddr *) namebuf, &len);
#endif
    /* 
    fd = PerlSock_accept(PerlIO_fileno(IoIFP(gstio)), (struct sockaddr *) namebuf, &len);
    */
#if defined(OEMVS)
    if (len == 0) {
	/* Some platforms indicate zero length when an AF_UNIX client is
	 * not bound. Simulate a non-zero-length sockaddr structure in
	 * this case. */
	namebuf[0] = 0;        /* sun_len */
	namebuf[1] = AF_UNIX;  /* sun_family */
	len = 2;
    }
#endif

    if (fd < 0)
	goto badexit;
    if (IoIFP(nstio))
	do_close(ngv, FALSE);
    IoIFP(nstio) = PerlIO_fdopen(fd, "r"SOCKET_OPEN_MODE);
    IoOFP(nstio) = PerlIO_fdopen(fd, "w"SOCKET_OPEN_MODE);
    IoTYPE(nstio) = IoTYPE_SOCKET;
    if (!IoIFP(nstio) || !IoOFP(nstio)) {
	if (IoIFP(nstio)) PerlIO_close(IoIFP(nstio));
	if (IoOFP(nstio)) PerlIO_close(IoOFP(nstio));
	if (!IoIFP(nstio) && !IoOFP(nstio)) PerlLIO_close(fd);
	goto badexit;
    }
#if 0
    /* accept4(2) sets O_CLOEXEC. */
#if defined(HAS_FCNTL) && defined(F_SETFD)
    fcntl(fd, F_SETFD, fd > PL_maxsysfd);	/* ensure close-on-exec */
#endif
#endif

#ifdef __SCO_VERSION__
    len = sizeof (struct sockaddr_in); /* OpenUNIX 8 somehow truncates info */
#endif

    PUSHp(namebuf, len);
    RETURN;

nuts:
    Perl_report_evil_fh(ggv);
    SETERRNO(EBADF,SS_IVCHAN);

badexit:
    RETPUSHUNDEF;

}

MODULE = Devel::Accept4    PACKAGE = Devel::Accept4

PROTOTYPES: DISABLE

void
replace_accept()
CODE:
    PL_ppaddr[OP_ACCEPT] = my_accept;

