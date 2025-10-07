#!/usr/bin/perl
#
# BackupPC Unified Diagnostic Script
# 
# This comprehensive diagnostic script analyzes BackupPC 4.4.0 configuration
# for corruption issues caused by Data::Dumper serialization problems with 
# Perl 5.38.2. It detects all issues that backuppc_unified_fix.pl can repair.
#
# Author: GitHub Copilot Assistant
# Date: 2025-10-02
# Status: Production Ready - Matches unified fix script
#

use strict;
use warnings;
use Data::Dumper;
use File::Find;
use Time::HiRes qw(time);

# Global configuration variable
our %Conf;

# Configuration
my $BACKUPPC_CONF_DIR = '/etc/BackupPC';
my $BACKUPPC_PC_DIR = "$BACKUPPC_CONF_DIR/pc";
my $BACKUPPC_LIB_DIR = '/usr/local/BackupPC/lib';
my $LOG_FILE = '/tmp/backuppc_diagnostic_final.log';

# Tracking variables
my $total_files = 0;
my $files_with_issues = 0;
my $total_issues = 0;
my %issue_types;
my @critical_issues;
my @warnings;
my %statistics;

print "BackupPC Unified Configuration Diagnostic\n";
print "==========================================\n";
print "Comprehensive analysis for BackupPC 4.4.0 + Perl 5.38.2 issues\n";
print "Detects all issues that backuppc_unified_fix.pl can repair\n\n";

# Open log file
open(my $log_fh, '>', $LOG_FILE) or die "Cannot create log file $LOG_FILE: $!";
print $log_fh "BackupPC Diagnostic Log - " . localtime() . "\n";
print $log_fh "="x60 . "\n\n";

sub log_message {
    my ($message, $level) = @_;
    $level ||= 'INFO';
    my $formatted = "[$level] $message";
    print $formatted;
    print $log_fh $formatted;
}

# Function to detect Data::Dumper corruption patterns
sub detect_corruption_patterns {
    my ($content, $filename) = @_;
    my @issues;
    
    # Known hash configurations that should use {} not [] or ()
    # These are the same configs that the fix script corrects
    my @hash_configs = qw(
        CgiStatusHilightColor
        CgiUserConfigEdit
        BackupFilesExclude
        CgiExt2ContentType
        ClientShareName2Path
    );
    
    # Pattern 1: Hash configs using array brackets []
    foreach my $config (@hash_configs) {
        # Multi-line square brackets: $Conf{X} = [\n...\n];
        if ($content =~ /\$Conf\{$config\}\s*=\s*\[\s*\n/) {
            push @issues, {
                type => 'HASH_AS_ARRAY_MULTILINE',
                config => $config,
                severity => 'CRITICAL',
                description => "Hash configuration $config incorrectly uses [] (multi-line) instead of {}",
                line => get_line_number($content, "\$Conf\{$config\}")
            };
        }
        
        # Inline square brackets with hash syntax: $Conf{X} = [key=>val];
        if ($content =~ /\$Conf\{$config\}\s*=\s*\[[^\]]*=>[^\]]*\];/) {
            push @issues, {
                type => 'HASH_AS_ARRAY_INLINE',
                config => $config,
                severity => 'CRITICAL',
                description => "Hash configuration $config incorrectly uses [] (inline hash) instead of {}",
                line => get_line_number($content, "\$Conf\{$config\}")
            };
        }
    }

    # Pattern 2: Hash configs using parentheses ()
    foreach my $config (@hash_configs) {
        # Multi-line parentheses: $Conf{X} = (\n...\n);
        if ($content =~ /\$Conf\{$config\}\s*=\s*\(\s*\n/) {
            push @issues, {
                type => 'HASH_AS_PAREN_MULTILINE',
                config => $config,
                severity => 'CRITICAL',
                description => "Hash configuration $config incorrectly uses () (multi-line list) instead of {}",
                line => get_line_number($content, "\$Conf\{$config\}")
            };
        }
        
        # Inline parentheses: $Conf{X} = ('a','b'); (but not key=>value)
        if ($content =~ /\$Conf\{$config\}\s*=\s*\(([^\)]*)\);/ && $1 !~ /=>/) {
            push @issues, {
                type => 'HASH_AS_PAREN_INLINE',
                config => $config,
                severity => 'CRITICAL',
                description => "Hash configuration $config incorrectly uses () (inline list) instead of {}",
                line => get_line_number($content, "\$Conf\{$config\}")
            };
        }
    }
    
    # Pattern 3: Array configs using parentheses () instead of []
    # Match any $Conf{X} = (...); that is NOT in the hash_configs list
    my $hash_pattern = join('|', @hash_configs);
    while ($content =~ /\$Conf\{([^}]+)\}\s*=\s*\(/g) {
        my $config = $1;
        # Skip if it's a known hash config (already handled above)
        next if $config =~ /^($hash_pattern)$/;
        
        # Get the context to see if it's likely an array or hash
        my $pos = pos($content);
        my $context = substr($content, $pos - 50, 100);
        
        # Skip if this contains hash syntax (key => value)
        next if $context =~ /=>/;
        
        # Check if multi-line
        my $is_multiline = ($context =~ /\(\s*\n/);
        
        push @issues, {
            type => $is_multiline ? 'ARRAY_AS_PAREN_MULTILINE' : 'ARRAY_AS_PAREN_INLINE',
            config => $config,
            severity => 'HIGH',
            description => "Array configuration $config uses () instead of [] " . 
                          ($is_multiline ? "(multi-line)" : "(inline)"),
            line => get_line_number($content, "\$Conf\{$config\}")
        };
    }
    
    # Pattern 4: Missing semicolons
    while ($content =~ /\$Conf\{([^}]+)\}\s*=\s*[{\[].+?[}\]]\s*$/gm) {
        my $config = $1;
        my $match = $&;
        if ($match !~ /;$/) {
            push @issues, {
                type => 'MISSING_SEMICOLON',
                config => $config,
                severity => 'MEDIUM',
                description => "Configuration $config missing trailing semicolon",
                line => get_line_number($content, "\$Conf\{$config\}")
            };
        }
    }
    
    # Pattern 5: CgiNavBarLinks should be an arrayref - check for hash brackets
    if ($content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\{/) {
        push @issues, {
            type => 'CGINAVRBARLINKS_AS_HASH',
            config => 'CgiNavBarLinks',
            severity => 'CRITICAL',
            description => "CgiNavBarLinks incorrectly uses {} (hash) instead of [] (arrayref)",
            line => get_line_number($content, 'CgiNavBarLinks.*=.*\{')
        };
    }
    
    # Pattern 6: CgiNavBarLinks with parentheses
    if ($content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\(/) {
        push @issues, {
            type => 'CGINAVRBARLINKS_WITH_PARENS',
            config => 'CgiNavBarLinks',
            severity => 'CRITICAL',
            description => "CgiNavBarLinks incorrectly uses () instead of [] (arrayref)",
            line => get_line_number($content, 'CgiNavBarLinks.*=.*\(')
        };
    }
    
    # Pattern 7: Nested structure corruption
    if ($content =~ /\$Conf\{[^}]+\}\s*=\s*\{\s*\[/) {
        push @issues, {
            type => 'NESTED_CORRUPTION',
            config => 'UNKNOWN',
            severity => 'HIGH',
            description => "Detected nested structure corruption (hash containing array with wrong brackets)",
            line => 0
        };
    }
    
    return @issues;
}

# Function to get approximate line number
sub get_line_number {
    my ($content, $pattern) = @_;
    my @lines = split /\n/, $content;
    for my $i (0..$#lines) {
        if ($lines[$i] =~ /$pattern/) {
            return $i + 1;
        }
    }
    return 0;
}

# Function to test configuration loading (for main config only)
sub test_config_loading {
    my ($config_file) = @_;
    
    # Create test script
    my $test_script = "/tmp/config_test_$$.pl";
    open(my $fh, '>', $test_script) or return (0, "Cannot create test script");
    
    print $fh qq{
use strict;
use warnings;
use lib '/usr/local/BackupPC/lib';

# Suppress warnings for this test
local \$SIG{__WARN__} = sub { };

our %Conf;
eval {
    do '$config_file';
};

if (\$@) {
    print "SYNTAX_ERROR: \$@\\n";
    exit 1;
}

# Test specific configurations that commonly have issues
my \@test_configs = qw(CgiStatusHilightColor CgiUserConfigEdit BackupFilesExclude CgiNavBarLinks CgiExt2ContentType ClientShareName2Path);
my %results;

foreach my \$config (\@test_configs) {
    if (exists \$Conf{\$config}) {
        my \$ref_type = ref(\$Conf{\$config});
        \$results{\$config} = \$ref_type || 'SCALAR';
    }
}

# Explicitly check CgiNavBarLinks is an arrayref
if (exists \$Conf{CgiNavBarLinks}) {
    my \$ref_type = ref(\$Conf{CgiNavBarLinks});
    unless (\$ref_type eq 'ARRAY') {
        print "WARNING: CgiNavBarLinks is not an arrayref (found \$ref_type)\\n";
    }
}

use Data::Dumper;
\$Data::Dumper::Terse = 1;
\$Data::Dumper::Indent = 0;
print "CONFIG_TYPES: " . Dumper(\\%results) . "\\n";
exit 0;
};
    
    close($fh);
    
    # Run test
    my $output = `perl '$test_script' 2>&1`;
    my $exit_code = $? >> 8;
    unlink($test_script);
    
    return ($exit_code == 0, $output);
}

# Function to analyze a single file
sub analyze_file {
    my ($filepath) = @_;
    
    log_message("Analyzing: $filepath\n");
    $total_files++;
    
    # Read file
    open(my $fh, '<', $filepath) or do {
        log_message("  ERROR: Cannot read file: $!\n", 'ERROR');
        return;
    };
    my $content = do { local $/; <$fh> };
    close($fh);
    
    # Basic file info
    my $size = length($content);
    my $lines = ($content =~ tr/\n//) + 1;
    $statistics{total_size} += $size;
    $statistics{total_lines} += $lines;
    
    log_message("  Size: $size bytes, Lines: $lines\n");
    
    # Detect issues
    my @issues = detect_corruption_patterns($content, $filepath);
    
    if (@issues) {
        $files_with_issues++;
        $total_issues += scalar(@issues);
        
        log_message("  ISSUES FOUND: " . scalar(@issues) . "\n", 'WARN');
        
        foreach my $issue (@issues) {
            $issue_types{$issue->{type}}++;
            
            my $msg = sprintf("    [%s] Line %d: %s (%s)\n", 
                $issue->{severity}, $issue->{line}, 
                $issue->{description}, $issue->{config});
            log_message($msg, $issue->{severity});
            
            if ($issue->{severity} eq 'CRITICAL') {
                push @critical_issues, {%$issue, file => $filepath};
            } elsif ($issue->{severity} eq 'HIGH') {
                push @warnings, {%$issue, file => $filepath};
            }
        }
    } else {
        log_message("  No corruption patterns detected\n");
    }
    
    # Test actual loading if this is a config file
    if ($filepath =~ /config\.pl$/ || $filepath =~ /\.pl$/) {
        my ($load_ok, $load_output) = test_config_loading($filepath);
        
        if ($load_ok) {
            log_message("  Config loading: SUCCESS\n");
            if ($load_output =~ /CONFIG_TYPES: (.+)/) {
                my $types_str = $1;
                log_message("  Data types: $types_str\n");
                
                # Check for type mismatches
                if ($types_str =~ /CgiStatusHilightColor[^}]*ARRAY/) {
                    push @critical_issues, {
                        type => 'TYPE_MISMATCH',
                        config => 'CgiStatusHilightColor',
                        severity => 'CRITICAL',
                        description => 'CgiStatusHilightColor loaded as ARRAY instead of HASH',
                        file => $filepath,
                        line => 0
                    };
                }
                if ($types_str =~ /CgiUserConfigEdit[^}]*ARRAY/) {
                    push @critical_issues, {
                        type => 'TYPE_MISMATCH',
                        config => 'CgiUserConfigEdit',
                        severity => 'CRITICAL',
                        description => 'CgiUserConfigEdit loaded as ARRAY instead of HASH',
                        file => $filepath,
                        line => 0
                    };
                }
                # Check other hash configs
                foreach my $cfg (qw(BackupFilesExclude CgiNavBarLinks CgiExt2ContentType ClientShareName2Path)) {
                    if ($types_str =~ /$cfg[^}]*ARRAY/) {
                        push @critical_issues, {
                            type => 'TYPE_MISMATCH',
                            config => $cfg,
                            severity => 'CRITICAL',
                            description => "$cfg loaded as ARRAY instead of HASH",
                            file => $filepath,
                            line => 0
                        };
                    }
                }
            }
        } else {
            log_message("  Config loading: FAILED\n", 'ERROR');
            log_message("  Error: $load_output\n", 'ERROR');
            
            push @critical_issues, {
                type => 'LOAD_ERROR',
                config => 'FILE',
                severity => 'CRITICAL',
                description => "Configuration file fails to load: $load_output",
                file => $filepath,
                line => 0
            };
        }
    }
    
    log_message("\n");
}

print "1. Configuration File Syntax Analysis:\n";
my @config_files = (
    "/etc/BackupPC/config.pl",
    glob("/etc/BackupPC/pc/*.pl")
);

my $syntax_issues = 0;
foreach my $file (@config_files) {
    next if $file =~ /\.old$|\.backup_/;
    next unless -f $file;
    
    my $result = system("perl -c '$file' 2>/dev/null");
    if ($result != 0) {
        print "  ✗ SYNTAX ERROR: $file\n";
        $syntax_issues++;
    }
}

if ($syntax_issues == 0) {
    print "  ✓ All configuration files have valid Perl syntax\n";
} else {
    print "  ✗ Found $syntax_issues files with syntax errors\n";
}

print "\n2. Data::Dumper Corruption Pattern Check:\n";
my $corruption_found = 0;

# Analyze each config file for corruption patterns
foreach my $file (@config_files) {
    next if $file =~ /\.old$|\.backup_/;
    next unless -f $file;
    
    analyze_file($file);
}

if ($files_with_issues == 0) {
    print "  ✓ No Data::Dumper corruption patterns found in file analysis\n";
}

# Additional quick scan for summary
print "\n  Quick Scan Summary:\n";
foreach my $file (@config_files) {
    next if $file =~ /\.old$|\.backup_/;
    next unless -f $file;
    
    open(my $fh, '<', $file) or next;
    my $content = do { local $/; <$fh> };
    close($fh);
    
    my $file_issues = 0;
    
    # Check for array syntax using parentheses (corrupted)
    # Skip known hash configs when checking arrays (but CgiNavBarLinks should be array)
    my @hash_configs = qw(CgiStatusHilightColor CgiUserConfigEdit BackupFilesExclude CgiExt2ContentType ClientShareName2Path);
    my $hash_pattern = join('|', @hash_configs);
    
    # Special check for CgiNavBarLinks corruption (should be arrayref)
    if ($content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\{/) {
        print "  ✗ CORRUPTED ARRAY in $file: CgiNavBarLinks (uses {} instead of [])\n";
        $file_issues++;
    }
    if ($content =~ /\$Conf\{CgiNavBarLinks\}\s*=\s*\(/) {
        print "  ✗ CORRUPTED ARRAY in $file: CgiNavBarLinks (uses () instead of [])\n";
        $file_issues++;
    }
    
    while ($content =~ /\$Conf\{([^}]+)\}\s*=\s*\(/g) {
        my $config = $1;
        next if $config =~ /^($hash_pattern)$/;
        
        # Get context to check if it contains =>
        my $pos = pos($content);
        my $start = $pos > 100 ? $pos - 100 : 0;
        my $context = substr($content, $start, 200);
        next if $context =~ /=>/;
        
        print "  ✗ CORRUPTED ARRAY in $file: $config (uses () instead of [])\n";
        $file_issues++;
    }
    
    # Check for hash syntax using square brackets (corrupted)
    foreach my $config (@hash_configs) {
        if ($content =~ /\$Conf\{$config\}\s*=\s*\[/) {
            print "  ✗ CORRUPTED HASH in $file: $config (uses [] instead of {})\n";
            $file_issues++;
        }
    }
    
    # Check for hash syntax using parentheses (corrupted)
    foreach my $config (@hash_configs) {
        if ($content =~ /\$Conf\{$config\}\s*=\s*\(/) {
            # Check if it contains => (already a hash, just wrong brackets)
            my $pos = pos($content);
            my $context = substr($content, $pos, 200);
            if ($context !~ /=>/) {
                print "  ✗ CORRUPTED HASH in $file: $config (uses () list instead of {})\n";
                $file_issues++;
            }
        }
    }
    
    $corruption_found += $file_issues;
}

if ($corruption_found == 0) {
    print "  ✓ No Data::Dumper corruption patterns found\n";
}

# Test 3: BackupPC Runtime Configuration Check
print "\n3. BackupPC Runtime Configuration Check:\n";

eval {
    require BackupPC::Lib;
    my $bpc = BackupPC::Lib->new();
    
    if (!$bpc) {
        print "  ✗ Cannot initialize BackupPC::Lib\n";
        return;
    }
    
    my $config = $bpc->ConfigDataRead();
    
    # Check CgiStatusHilightColor (the main culprit)
    if (exists $config->{CgiStatusHilightColor}) {
        my $ref_type = ref($config->{CgiStatusHilightColor});
        if ($ref_type eq 'HASH') {
            print "  ✓ CgiStatusHilightColor is correctly a HASH\n";
            print "    Keys: " . join(", ", sort keys %{$config->{CgiStatusHilightColor}}) . "\n";
        } elsif ($ref_type eq 'ARRAY') {
            print "  ✗ CgiStatusHilightColor is incorrectly an ARRAY (will cause Summary.pm error)\n";
        } else {
            print "  ✗ CgiStatusHilightColor is neither HASH nor ARRAY: $ref_type\n";
        }
    } else {
        print "  ✗ CgiStatusHilightColor not found in configuration\n";
    }
    
    # Check other critical hash configurations
    my %expected_hashes = (
        'CgiUserConfigEdit' => 'User configuration edit permissions',
        'BackupFilesExclude' => 'File exclusion patterns',
        'CgiNavBarLinks' => 'Navigation bar links',
        'CgiExt2ContentType' => 'Extension to content type mapping',
        'ClientShareName2Path' => 'Client share name to path mapping'
    );
    
    foreach my $config_name (sort keys %expected_hashes) {
        if (exists $config->{$config_name}) {
            my $ref_type = ref($config->{$config_name});
            if ($ref_type eq 'HASH') {
                print "  ✓ $config_name is correctly a HASH\n";
            } else {
                print "  ✗ $config_name is $ref_type (should be HASH)\n";
            }
        }
    }
};

if ($@) {
    print "  ✗ ERROR testing BackupPC configuration: $@\n";
}

# Test 4: Web Interface Error Check
print "\n4. Recent Web Interface Error Check:\n";

if (-f "/var/log/apache2/error.log") {
    my $recent_errors = `sudo tail -20 /var/log/apache2/error.log | grep -c "Not.*reference.*BackupPC" 2>/dev/null || echo 0`;
    chomp $recent_errors;
    
    if ($recent_errors > 0) {
        print "  ✗ Found $recent_errors recent BackupPC reference errors in Apache log\n";
        print "    Run: sudo tail -20 /var/log/apache2/error.log | grep BackupPC\n";
    } else {
        print "  ✓ No recent BackupPC reference errors in Apache log\n";
    }
} else {
    print "  - Apache error log not accessible\n";
}

# Test 5: Service Status Check
print "\n5. BackupPC Service Status:\n";

my $service_status = `systemctl is-active backuppc 2>/dev/null`;
chomp $service_status;

if ($service_status eq 'active') {
    print "  ✓ BackupPC service is running\n";
} else {
    print "  ✗ BackupPC service is $service_status\n";
    print "    Run: sudo systemctl start backuppc\n";
}

# Summary
print "\n" . "="x70 . "\n";
print "DIAGNOSTIC SUMMARY\n";
print "="x70 . "\n";

print "Files scanned:       $total_files\n";
print "Files with issues:   $files_with_issues\n";
print "Total issues found:  $total_issues\n";

if ($total_issues > 0) {
    print "\nIssue Breakdown:\n";
    foreach my $type (sort keys %issue_types) {
        print "  $type: $issue_types{$type}\n";
    }
}

if (scalar(@critical_issues) > 0) {
    print "\n" . "="x70 . "\n";
    print "CRITICAL ISSUES (" . scalar(@critical_issues) . ")\n";
    print "="x70 . "\n";
    foreach my $issue (@critical_issues) {
        print "  [$issue->{severity}] $issue->{file}\n";
        print "    Config: $issue->{config}\n";
        print "    Issue: $issue->{description}\n";
        print "\n";
    }
}

print "\n" . "="x70 . "\n";

if ($syntax_issues == 0 && $corruption_found == 0 && $total_issues == 0) {
    print "✓ CONFIGURATION APPEARS HEALTHY\n";
    print "="x70 . "\n";
    print "\nNo Data::Dumper corruption patterns detected.\n";
    print "\nIf you're still experiencing issues:\n";
    print "1. Restart BackupPC: sudo systemctl restart backuppc\n";
    print "2. Test web interface\n";
    print "3. Check Apache error log for new errors\n";
} else {
    print "✗ CONFIGURATION ISSUES FOUND\n";
    print "="x70 . "\n";
    print "\nThe following issues can be automatically fixed:\n";
    print "  - Hash configs using [] or () instead of {}\n";
    print "  - Array configs using () instead of []\n";
    print "  - Type mismatches in loaded configuration\n";
    print "\nRecommended actions:\n";
    print "1. Run the unified fix script:\n";
    print "   sudo perl backuppc_unified_fix.pl\n";
    print "2. Restart BackupPC after fixes:\n";
    print "   sudo systemctl restart backuppc\n";
    print "3. Re-run this diagnostic:\n";
    print "   perl $0\n";
    print "4. Test the web interface\n";
}

print "\nLog file: $LOG_FILE\n";
print "\nFor BackupPC 4.4.0 + Perl 5.38.2 compatibility issues, see:\n";
print "https://github.com/backuppc/backuppc/issues\n";

close($log_fh);

exit($syntax_issues + $corruption_found + $total_issues);