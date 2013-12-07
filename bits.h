#pragma once

#ifndef min
#define min(a,b)	((a)<(b)?(a):(b))
#endif /* min */
#ifndef max
#define max(a,b)	((a)>(b)?(a):(b))
#endif /* max */

/* branch predictor hints - GCC specific */
#define likely(x)       __builtin_expect((x),1)
#define unlikely(x)     __builtin_expect((x),0)

