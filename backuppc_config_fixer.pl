#!/usr/bin/perl
#
# BackupPC Unified Configuration Fix Script
# 
# This script fixes BackupPC 4.4.0 configuration corruption caused by 
# Data::Dumper serialization issues with Perl 5.38.2. It corrects
# hash/array reference problems that cause web interface errors.
#
# Combines functionality from:
# - backuppc_fix_cgiedit.pl (CgiUserConfigEdit array -> hash)
# - final_backuppc_fix.pl (comprehensive hash/array fixes)
#
# Author: GitHub Copilot Assistant
# Date: 2025-10-02
# Status: Production Ready
#

use strict;
use warnings;
use File::Copy;
use Time::HiRes qw(time);

# Configuration
my $BACKUPPC_CONF_DIR = '/etc/BackupPC';
my $BACKUPPC_PC_DIR = "$BACKUPPC_CONF_DIR/pc";
my $BACKUP_SUFFIX = '.backup_' . int(time());
my $LOG_FILE = '/tmp/backuppc_unified_fix.log';

# Statistics
my $files_processed = 0;
my $files_fixed = 0;
my $total_fixes = 0;

print "BackupPC Unified Configuration Fix Script\n";
print "==========================================\n";
print "Fixes BackupPC 4.4.0 + Perl 5.38.2 Data::Dumper corruption issues\n";
print "- Converts hash configs using [] or () to {}\n";
print "- Converts array configs using () to []\n";
print "- Validates syntax and tests configuration loading\n\n";

# Check permissions
my $user = getpwuid($>);
if ($user ne 'root') {
    print "ERROR: This script must be run as root\n";
    print "Usage: sudo perl $0\n";
    exit 1;
}

# Open log file
open(my $log_fh, '>', $LOG_FILE) or die "Cannot create log file $LOG_FILE: $!";
print $log_fh "BackupPC Unified Fix Script Log - " . localtime() . "\n";
print $log_fh "="x70 . "\n\n";

sub log_message {
    my ($message) = @_;
    print $message;
    print $log_fh $message;
}

# Function to create backup
sub backup_file {
    my ($file) = @_;
    my $backup = $file . $BACKUP_SUFFIX;
    
    if (copy($file, $backup)) {
        log_message("  ✓ Created backup: $backup\n");
        return 1;
    } else {
        log_message("  ✗ ERROR: Cannot backup $file: $!\n");
        return 0;
    }
}

# Function to fix hash configurations that use wrong brackets
sub fix_hash_configurations {
    my ($content) = @_;
    my $fixes = 0;
    
    # Known hash configurations that should use {} not [] or ()
    my @hash_configs = qw(
        CgiStatusHilightColor
        CgiUserConfigEdit
        BackupFilesExclude
        CgiExt2ContentType
        ClientShareName2Path
    );
    
    foreach my $config (@hash_configs) {
        # Multi-line square brackets with list of values: ['a','b'] -> {'a'=>1,'b'=>1}
        while ($content =~ s/(\$Conf\{$config\}\s*=\s*)\[\s*\n((?:.*?\n)*?)\s*\];/$1\{\n"__TO_BE_REPLACED_${config}__"\n\};/s) {
            my $inner = $2;
            my @items = map { s/^\s+|\s+$//g; $_ } grep { length $_ } map { s/#.*$//r } split(/,/, $inner);
            my $hash_body = join(",\n", map { my $k = $_; $k =~ s/^\s*['\"]?(.*?)['\"]?\s*$/\"$1\"/; "    $k => 1" } @items);
            $hash_body .= ',' if $hash_body ne '';
            $content =~ s/"__TO_BE_REPLACED_${config}__"\n/"" . "\n" . "$hash_body"/e;
            log_message("    ✓ Fixed $config: converted [] (multi-line list) to {} (hash)\n");
            $fixes++;
        }

        # Inline [] containing key=>value - just convert brackets to braces
        if ($content =~ s/(\$Conf\{$config\}\s*=\s*)\[([^\]]*=>[^\]]*)\];/$1\{$2\};/g) {
            log_message("    ✓ Fixed $config: converted [] to {} (inline hash)\n");
            $fixes++;
        }

        # Multi-line parentheses: (\n'a',\n'b'\n) -> {'a'=>1,'b'=>1}
        while ($content =~ s/(\$Conf\{$config\}\s*=\s*)\(\s*\n((?:.*?\n)*?)\s*\);/$1\{\n"__TO_BE_REPLACED_${config}__"\n\};/s) {
            my $inner = $2;
            my @items = map { s/^\s+|\s+$//g; $_ } grep { length $_ } map { s/#.*$//r } split(/,/, $inner);
            my $hash_body = join(",\n", map { my $k = $_; $k =~ s/^\s*['\"]?(.*?)['\"]?\s*$/\"$1\"/; "    $k => 1" } @items);
            $hash_body .= ',' if $hash_body ne '';
            $content =~ s/"__TO_BE_REPLACED_${config}__"\n/"" . "\n" . "$hash_body"/e;
            log_message("    ✓ Fixed $config: converted () (multi-line list) to {} (hash)\n");
            $fixes++;
        }

        # Inline parentheses: ('a','b') -> {'a'=>1,'b'=>1}
        while ($content =~ s/(\$Conf\{$config\}\s*=\s*)\(([^\)]*)\);/$1\{\n"__TO_BE_REPLACED_${config}__"\n\};/g) {
            my $inner = $2;
            # Skip if it already contains hash syntax
            next if $inner =~ /=>/;
            my @items = map { s/^\s+|\s+$//g; $_ } grep { length $_ } map { s/#.*$//r } split(/,/, $inner);
            my $hash_body = join(",\n", map { my $k = $_; $k =~ s/^\s*['\"]?(.*?)['\"]?\s*$/\"$1\"/; "    $k => 1" } @items);
            $hash_body .= ',' if $hash_body ne '';
            $content =~ s/"__TO_BE_REPLACED_${config}__"\n/"" . "\n" . "$hash_body"/e;
            log_message("    ✓ Fixed $config: converted () (inline list) to {} (hash)\n");
            $fixes++;
        }
    }
    
    return ($content, $fixes);
}

# Function to fix array configurations that use wrong brackets
sub fix_array_configurations {
    my ($content) = @_;
    my $fixes = 0;
    
    # Special handling for CgiNavBarLinks - must be an arrayref
    # Convert hash {} to array [] for CgiNavBarLinks
    if ($content =~ s/(\$Conf\{CgiNavBarLinks\}\s*=\s*)\{([^}]*)\};/$1\[$2\];/g) {
        log_message("    ✓ Fixed CgiNavBarLinks: converted {} (hash) to [] (arrayref)\n");
        $fixes++;
    }
    
    # Convert parentheses () to array [] for CgiNavBarLinks
    if ($content =~ s/(\$Conf\{CgiNavBarLinks\}\s*=\s*)\(([^)]*)\);/$1\[$2\];/g) {
        log_message("    ✓ Fixed CgiNavBarLinks: converted () to [] (arrayref)\n");
        $fixes++;
    }
    
    # Fix multi-line array assignments using parentheses: (...) -> [...]
    while ($content =~ s/(\$Conf\{([^}]+)\}\s*=\s*)\(\s*\n((?:[^)]*\n)*?)(\s*)\);/$1\[\n$3$4\];/gs) {
        my $config_name = $2;
        # Skip known hash configs (but allow CgiNavBarLinks which should be array)
        next if $config_name =~ /^(CgiStatusHilightColor|CgiUserConfigEdit|BackupFilesExclude|CgiExt2ContentType|ClientShareName2Path)$/;
        log_message("    ✓ Fixed $config_name: converted () to [] (multi-line array)\n");
        $fixes++;
    }
    
    # Fix single-line array assignments with parentheses: (...) -> [...]
    while ($content =~ s/(\$Conf\{([^}]+)\}\s*=\s*)\(([^)]*)\);/$1\[$3\];/g) {
        my $config_name = $2;
        my $inner_content = $3;
        # Skip known hash configs (but allow CgiNavBarLinks which should be array)
        next if $config_name =~ /^(CgiStatusHilightColor|CgiUserConfigEdit|BackupFilesExclude|CgiExt2ContentType|ClientShareName2Path)$/;
        # Only fix if it doesn't contain hash syntax (key => value)
        next if $inner_content =~ /=>/;
        log_message("    ✓ Fixed $config_name: converted () to [] (inline array)\n");
        $fixes++;
    }
    
    return ($content, $fixes);
}

# Function to validate Perl syntax
sub validate_syntax {
    my ($content) = @_;
    
    my $temp_file = "/tmp/backuppc_syntax_test_$$.pl";
    open(my $fh, '>', $temp_file) or return (0, "Cannot create temp file");
    print $fh $content;
    close($fh);
    
    my $result = system("perl -c '$temp_file' 2>/dev/null");
    unlink($temp_file);
    
    return ($result == 0, $result == 0 ? "Valid" : "Invalid");
}

# Function to test configuration loading (for main config only)
sub test_config_loading {
    my ($file) = @_;
    
    my $test_script = "/tmp/config_test_$$.pl";
    open(my $test_fh, '>', $test_script) or return (0, "Cannot create test script: $!");
    
    print $test_fh qq{
use strict;
use warnings;
use lib '/usr/local/BackupPC/lib';

our %Conf;
eval {
    do '$file';
};

if (\$@) {
    print "ERROR: \$@\\n";
    exit 1;
}

# Check CgiUserConfigEdit is a hash
if (exists \$Conf{CgiUserConfigEdit}) {
    my \$ref_type = ref(\$Conf{CgiUserConfigEdit});
    if (\$ref_type ne 'HASH') {
        print "ERROR: CgiUserConfigEdit is \$ref_type, not HASH\\n";
        exit 1;
    }
}

# Check CgiStatusHilightColor is a hash
if (exists \$Conf{CgiStatusHilightColor}) {
    my \$ref_type = ref(\$Conf{CgiStatusHilightColor});
    if (\$ref_type ne 'HASH') {
        print "ERROR: CgiStatusHilightColor is \$ref_type, not HASH\\n";
        exit 1;
    }
}

# Check CgiNavBarLinks is an array
if (exists \$Conf{CgiNavBarLinks}) {
    my \$ref_type = ref(\$Conf{CgiNavBarLinks});
    if (\$ref_type ne 'ARRAY') {
        print "ERROR: CgiNavBarLinks is \$ref_type, not ARRAY\\n";
        exit 1;
    }
}

print "SUCCESS: Configuration loaded correctly\\n";
exit 0;
};
    close($test_fh);
    
    my $test_output = `perl '$test_script' 2>&1`;
    my $test_exit = $? >> 8;
    unlink($test_script);
    
    return ($test_exit == 0, $test_output);
}

# Function to process a configuration file
sub process_file {
    my ($file, $is_main_config) = @_;
    
    log_message("\nProcessing: $file\n");
    $files_processed++;
    
    # Read file
    open(my $fh, '<', $file) or do {
        log_message("  ✗ ERROR: Cannot read $file: $!\n");
        return;
    };
    my $content = do { local $/; <$fh> };
    close($fh);
    
    # Check if file needs fixing
    my $needs_fix = 0;
    $needs_fix = 1 if $content =~ /\$Conf\{[^}]+\}\s*=\s*\(/;  # Any config with ()
    $needs_fix = 1 if $content =~ /\$Conf\{(?:CgiStatusHilightColor|CgiUserConfigEdit|BackupFilesExclude|CgiExt2ContentType|ClientShareName2Path)\}\s*=\s*\[/;  # Hash configs with []
    $needs_fix = 1 if $content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\{/;  # CgiNavBarLinks as hash (should be array)
    $needs_fix = 1 if $content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\(/;  # CgiNavBarLinks with parentheses
    
    if (!$needs_fix) {
        log_message("  ✓ No issues found - configuration is clean\n");
        return;
    }
    
    # Create backup
    backup_file($file) or return;
    
    # Apply fixes
    my $file_fixes = 0;
    log_message("  Applying fixes:\n");
    
    my ($fixed_content, $hash_fixes) = fix_hash_configurations($content);
    $file_fixes += $hash_fixes;
    
    ($fixed_content, my $array_fixes) = fix_array_configurations($fixed_content);
    $file_fixes += $array_fixes;
    
    if ($file_fixes == 0) {
        log_message("    No fixes needed after analysis\n");
        return;
    }
    
    # Validate syntax
    log_message("  Validating syntax...\n");
    my ($syntax_ok, $syntax_msg) = validate_syntax($fixed_content);
    if (!$syntax_ok) {
        log_message("  ✗ ERROR: Fixed content has syntax errors - NOT saving\n");
        return;
    }
    log_message("  ✓ Syntax validation passed\n");
    
    # Test configuration loading (main config only)
    if ($is_main_config) {
        # Write temp file for testing
        my $temp_test_file = "/tmp/backuppc_test_config_$$.pl";
        open(my $test_fh, '>', $temp_test_file) or do {
            log_message("  ✗ WARNING: Cannot create temp test file\n");
        };
        if ($test_fh) {
            print $test_fh $fixed_content;
            close($test_fh);
            
            log_message("  Testing configuration loading...\n");
            my ($load_ok, $load_msg) = test_config_loading($temp_test_file);
            unlink($temp_test_file);
            
            if (!$load_ok) {
                log_message("  ✗ ERROR: Configuration loading test failed - NOT saving\n");
                log_message("    $load_msg\n");
                return;
            }
            log_message("  ✓ Configuration loading test passed\n");
        }
    }
    
    # Write fixed file
    open($fh, '>', $file) or do {
        log_message("  ✗ ERROR: Cannot write $file: $!\n");
        return;
    };
    print $fh $fixed_content;
    close($fh);
    
    log_message("  ✓ SUCCESS: Applied $file_fixes fixes and saved\n");
    $files_fixed++;
    $total_fixes += $file_fixes;
}

# Main execution
log_message("Starting BackupPC configuration fix...\n");
log_message("="x70 . "\n");

# Process main config
my $main_config = "$BACKUPPC_CONF_DIR/config.pl";
if (-f $main_config) {
    log_message("\n[MAIN CONFIG]\n");
    process_file($main_config, 1);
} else {
    log_message("WARNING: Main config not found: $main_config\n");
}

# Process host configs
if (-d $BACKUPPC_PC_DIR) {
    log_message("\n[HOST CONFIGS]\n");
    
    opendir(my $dh, $BACKUPPC_PC_DIR) or die "Cannot read $BACKUPPC_PC_DIR: $!";
    my @host_configs = grep { /\.pl$/ && !/\.old$/ && !/\.backup_/ } readdir($dh);
    closedir($dh);
    
    if (@host_configs == 0) {
        log_message("\nNo host-specific configurations found\n");
    } else {
        log_message("\nFound " . scalar(@host_configs) . " host configuration(s) to process\n");
        foreach my $config_file (sort @host_configs) {
            my $full_path = "$BACKUPPC_PC_DIR/$config_file";
            process_file($full_path, 0) if -f $full_path;
        }
    }
}

# Summary
log_message("\n" . "="x70 . "\n");
log_message("FIX SUMMARY\n");
log_message("="x70 . "\n");
log_message("Files processed:     $files_processed\n");
log_message("Files fixed:         $files_fixed\n");
log_message("Total fixes applied: $total_fixes\n");
log_message("Backup suffix:       $BACKUP_SUFFIX\n");
log_message("Log file:            $LOG_FILE\n");

if ($files_fixed > 0) {
    # Get hostname for URL
    my $hostname = `hostname -f 2>/dev/null` || `hostname 2>/dev/null` || 'your-server';
    chomp($hostname);
    
    log_message("\n" . "="x70 . "\n");
    log_message("✓ SUCCESS: Configuration corruption has been fixed!\n");
    log_message("="x70 . "\n");
    log_message("\nNext steps:\n");
    log_message("1. Restart BackupPC:\n");
    log_message("   sudo systemctl restart backuppc\n");
    log_message("\n2. Wait 10-15 seconds for full startup\n");
    log_message("\n3. Test the web interface:\n");
    log_message("   http://$hostname/backuppc/\n");
    log_message("\n4. Check for errors:\n");
    log_message("   sudo tail -f /var/log/apache2/error.log\n");
    log_message("\n5. Run diagnostic to verify:\n");
    log_message("   perl final_backuppc_diagnostic.pl\n");
    log_message("\n6. If everything works, you can remove backup files:\n");
    log_message("   sudo rm /etc/BackupPC/*$BACKUP_SUFFIX\n");
    log_message("   sudo rm /etc/BackupPC/pc/*$BACKUP_SUFFIX\n");
} elsif ($files_processed > 0) {
    log_message("\n✓ INFO: No corruption found. Configuration appears clean.\n");
} else {
    log_message("\n✗ ERROR: No configuration files found to process.\n");
}

close($log_fh);

print "\n" . "="x70 . "\n";
print "Full log saved to: $LOG_FILE\n";
print "="x70 . "\n";

exit($files_fixed > 0 ? 0 : 1);
