#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

int main(void)
{
    DXGI_SWAP_CHAIN_DESC desc = {0};
    IDXGISwapChain *swapchain;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    ID3D11Texture2D *backbuffer;
    ID3D11RenderTargetView *rtv;
    IDXGIDevice *dxgi_device;
    IDXGIAdapter *adapter;
    DXGI_ADAPTER_DESC adapter_desc;
    D3D_FEATURE_LEVEL level;
    LARGE_INTEGER freq, start, end;
    HMODULE d3d11;
    WCHAR path[MAX_PATH];
    HWND hwnd;
    HRESULT hr;
    int i;

    hwnd = CreateWindowA( "STATIC", "neutron d3d11 probe", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 640, 480, NULL, NULL, NULL, NULL );

    desc.BufferCount = 2;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.OutputWindow = hwnd;
    desc.SampleDesc.Count = 1;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    hr = D3D11CreateDeviceAndSwapChain( NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                                        &desc, &swapchain, &device, &level, &context );
    if (FAILED(hr)) { printf( "FAIL D3D11CreateDeviceAndSwapChain %#lx\n", hr ); return 1; }

    d3d11 = GetModuleHandleA( "d3d11.dll" );
    GetModuleFileNameW( d3d11, path, MAX_PATH );
    ID3D11Device_QueryInterface( device, &IID_IDXGIDevice, (void **)&dxgi_device );
    IDXGIDevice_GetAdapter( dxgi_device, &adapter );
    IDXGIAdapter_GetDesc( adapter, &adapter_desc );
    printf( "OK feature level %#x adapter \"%ls\" winemetal %s\n", level, adapter_desc.Description,
            GetModuleHandleA( "winemetal.dll" ) ? "loaded" : "absent" );

    IDXGISwapChain_GetBuffer( swapchain, 0, &IID_ID3D11Texture2D, (void **)&backbuffer );
    ID3D11Device_CreateRenderTargetView( device, (ID3D11Resource *)backbuffer, NULL, &rtv );

    QueryPerformanceFrequency( &freq );
    QueryPerformanceCounter( &start );
    for (i = 0; i < 300; i++)
    {
        MSG msg;
        float color[4] = { 0.1f, (i % 100) / 100.0f, 0.4f, 1.0f };
        while (PeekMessageA( &msg, NULL, 0, 0, PM_REMOVE )) DispatchMessageA( &msg );
        ID3D11DeviceContext_OMSetRenderTargets( context, 1, &rtv, NULL );
        ID3D11DeviceContext_ClearRenderTargetView( context, rtv, color );
        if (FAILED(hr = IDXGISwapChain_Present( swapchain, 0, 0 ))) { printf( "FAIL Present %#lx\n", hr ); return 1; }
    }
    QueryPerformanceCounter( &end );
    printf( "OK 300 frames, %.0f fps\n", 300.0 * freq.QuadPart / (end.QuadPart - start.QuadPart) );
    return 0;
}
