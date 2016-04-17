import numpy as np
cimport ctrlib
cimport libc.stdio
cimport numpy as np

cdef class Callback:
    cdef public object hvfcn
    
    def __cinit__(self, hvfcn):
        self.hvfcn = hvfcn

cdef void hvfcn_cb(void *userdata, int n, double *d, double* hv):
    cdef object self = <object> userdata
    _d = np.asarray(<np.float64_t[:n]> d)
    _hv = np.asarray(<np.float64_t[:n]> hv)
    _hv[:] = self.hvfcn(_d)

def prepare_memory(int itmax, double[::1] fwork not None):
    return ctrlib.trlib_prepare_memory(itmax, &fwork[0] if fwork.shape[0] > 0 else NULL)

def krylov_min(int init, double radius, double v_dot_g, double p_dot_Hp,
        int[::1] iwork not None, double [::1] fwork not None,
        equality = False, int itmax = 500, int itmax_lanczos = 100,
        double tol_rel_i = np.finfo(np.float).eps**.5, double tol_abs_i = 0.0,
        double tol_rel_b = np.finfo(np.float).eps**.3, double tol_abs_b = 0.0,
        double zero = np.finfo(np.float).eps, int verbose=0, refine = True,
        long[::1] timing = None, prefix=""):
    cdef long [:] timing_b
    if timing is None:
        ttiming = np.zeros([20], dtype=np.int)
        timing_b = ttiming
    else:
        timing_b = timing
    cdef int ret, action, iter, ityp
    cdef double flt1, flt2, flt3
    eprefix = prefix.encode('UTF-8')
    cdef char* cprefix = eprefix
    ret = ctrlib.trlib_krylov_min(init, radius, 1 if equality else 0, itmax, itmax_lanczos,
            tol_rel_i, tol_abs_i, tol_rel_b, tol_abs_b, zero, v_dot_g, p_dot_Hp,
            &iwork[0] if iwork.shape[0] > 0 else NULL, &fwork[0] if fwork.shape[0] > 0 else NULL,
            1 if refine else 0, verbose, 1, eprefix, <libc.stdio.FILE*> libc.stdio.stdout, &timing_b[0], &action, &iter, &ityp, &flt1, &flt2, &flt3)
    if timing is None:
        return ret, action, iter, ityp, flt1, flt2, flt3, ttiming
    else:
        return ret, action, iter, ityp, flt1, flt2, flt3

def solve_qp_cb(double radius, double [::1] g, hv, 
        double tol_rel_i = np.finfo(np.float).eps**.5, 
        double tol_rel_b = np.finfo(np.float).eps**.3,
        verbose=0):
    cdef ctrlib.trlib_driver_qp qp
    cdef int n = g.shape[0]
    if n == 0:
        return
    ctrlib.trlib_driver_malloc_qp(3, 0, n, 10*n, &qp)
    cb = Callback(hv)
    cdef ctrlib.trlib_driver_problem_op* pp = <ctrlib.trlib_driver_problem_op*> qp.problem
    cdef ctrlib.trlib_driver_problem_op problem = pp[0]
    ctrlib.trlib_driver_problem_set_hvcb(pp, <void *> cb, hvfcn_cb)
    qp.verbose = verbose
    qp.unicode = 1
    qp.stream = <libc.stdio.FILE*> libc.stdio.stdout
    qp.radius = radius
    qp.tol_rel_i = tol_rel_i
    qp.tol_rel_b = tol_rel_b
    _g = np.asarray(<np.float64_t[:n]> problem.grad)
    _g[:] = g[:]
    sol = np.empty_like(g)
    _sol = np.asarray(<np.float64_t[:n]> problem.sol)
    ctrlib.trlib_driver_solve_qp(&qp)
    sol[:] = _sol[:]
    ctrlib.trlib_driver_free_qp(&qp)
    return sol