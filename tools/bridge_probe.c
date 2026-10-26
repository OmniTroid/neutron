#include <windows.h>
#include <stdio.h>

typedef void *(__cdecl *CreateInterfaceFn)( const char *name, int *ret );
typedef int (__thiscall *CreateSteamPipeFn)( void *self );
typedef int (__thiscall *ConnectToGlobalUserFn)( void *self, int pipe );
typedef void *(__thiscall *GetInterfaceFn)( void *self, int user, int pipe, const char *version );
typedef const char *(__thiscall *GetPersonaNameFn)( void *self );

#define VTBL( obj, idx ) ((*(void ***)(obj))[idx])

int main( int argc, char **argv )
{
    const char *path = argc > 1 ? argv[1] : "C:\\Program Files (x86)\\Steam\\steamclient64.dll";
    HMODULE mod = LoadLibraryA( path );
    CreateInterfaceFn create;
    void *client, *friends;
    int pipe, user;

    if (getenv( "PROBE_OUT" )) freopen( getenv( "PROBE_OUT" ), "w", stdout );
    setvbuf( stdout, NULL, _IONBF, 0 );
    if (!mod) { printf( "FAIL load %s: %lu\n", path, GetLastError() ); return 1; }
    if (!(create = (CreateInterfaceFn)GetProcAddress( mod, "CreateInterface" ))) { printf( "FAIL no CreateInterface\n" ); return 1; }
    if (!(client = create( "SteamClient017", NULL ))) { printf( "FAIL CreateInterface(SteamClient017)\n" ); return 1; }
    printf( "OK ISteamClient017 %p\n", client );

    if (!(pipe = ((CreateSteamPipeFn)VTBL( client, 0 ))( client ))) { printf( "FAIL CreateSteamPipe (is Steam running?)\n" ); return 2; }
    if (!(user = ((ConnectToGlobalUserFn)VTBL( client, 2 ))( client, pipe ))) { printf( "FAIL ConnectToGlobalUser\n" ); return 2; }
    printf( "OK pipe %d user %d\n", pipe, user );

    if (!(friends = ((GetInterfaceFn)VTBL( client, 8 ))( client, user, pipe, "SteamFriends017" ))) { printf( "FAIL GetISteamFriends\n" ); return 3; }
    printf( "OK persona \"%s\"\n", ((GetPersonaNameFn)VTBL( friends, 0 ))( friends ) );
    return 0;
}
