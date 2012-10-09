use strict;
use warnings;

use Module::Build;

Module::Build->new(
    module_name => 'URI::Builder',
    requires => {
        'URI'              => '1.60',
        'namespace::clean' => '0.23',
    },
    configure_requires => {
        'Module::Build' => '0.38',
    },
    create_makefile_pl => 'small',
)->create_build_script;
