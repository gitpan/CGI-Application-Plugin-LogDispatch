use Module::Build;

Module::Build->new(
    module_name => 'CGI::Application::Plugin::LogDispatch',
    license => 'perl',
    requires => {
        'Log::Dispatch' => '0.21',
        'UNIVERSAL::require' => 0,
    },
    recommends => {
        'Sub::WrapPackages' => 0,
    },
    create_makefile_pl => 'traditional',
    create_readme => 1,
    dist_author => 'Cees Hek <cees@crtconsulting.ca>',
    dist_abstract => 'Plugin that adds Log::Dispatch support to CGI::Application',
)->create_build_script;

