//
//  SiriRemoteMicShared.h
//
//  The IPC contract between the HAL plug-in (consumer, runs inside coreaudiod) and the
//  router/producer (our app, runs as the user). A single-producer / single-consumer
//  lock-free ring of Float32 samples in POSIX shared memory.
//

#ifndef SIRI_REMOTE_MIC_SHARED_H
#define SIRI_REMOTE_MIC_SHARED_H

#include <stdint.h>
#include <stdatomic.h>

#define SRM_SHM_NAME     "/SiriRemoteMicAudio"
#define SRM_MAGIC        0x53524D31u
#define SRM_VERSION      1u
#define SRM_CHANNELS     1u
#define SRM_RING_FRAMES  65536u

#define SRM_BUILTIN_SHM_NAME  "/SiriRemoteMicBuiltin"

#define kSRM_RemoteStaleFrames  7200u
#define kSRM_SourceFadeFrames    240u

typedef struct {
    uint32_t          magic;
    uint32_t          version;
    uint32_t          sampleRate;
    uint32_t          channels;
    uint32_t          ringFrames;
    uint32_t          _pad;
    _Atomic uint32_t  producerActive;
    _Atomic uint64_t  writeIndex;
    float             ring[SRM_RING_FRAMES * SRM_CHANNELS];
} SRMSharedMemory;

#endif /* SIRI_REMOTE_MIC_SHARED_H */
