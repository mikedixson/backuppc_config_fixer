# BackupPC Configuration Fixer

Automated diagnostic and repair tools for BackupPC 4.4.0 configuration corruption caused by Data::Dumper serialization issues with Perl 5.38.2.

## 🔍 Problem Description

BackupPC 4.4.0 uses `Data::Dumper` to serialize configuration files. With Perl 5.38.2, Data::Dumper has changed behavior that causes configuration corruption:

- **Hash configurations** are incorrectly saved with array brackets `[]` or parentheses `()`
- **Array configurations** are saved with parentheses `()` instead of square brackets `[]`
- This causes BackupPC web interface errors like: `Not a HASH reference at .../BackupPC/CGI/Summary.pm`

### Affected Configurations

**Hash configs** that must use `{}`:
- `CgiStatusHilightColor` - Status highlight colors
- `CgiUserConfigEdit` - User configuration edit permissions  
- `BackupFilesExclude` - File exclusion patterns
- `CgiNavBarLinks` - Navigation bar links
- `CgiExt2ContentType` - Extension to content type mapping
- `ClientShareName2Path` - Client share name to path mapping

**Array configs** that must use `[]`:
- Any configuration using list syntax (multiple array configs exist)

## 📦 What's Included

### 1. `backuppc_config_diagnostic.pl`
**Comprehensive diagnostic tool** that analyzes BackupPC configuration for corruption.

**Features:**
- ✓ Detects all Data::Dumper corruption patterns
- ✓ Validates Perl syntax of config files
- ✓ Tests actual configuration loading and type checking
- ✓ Identifies specific issues with line numbers
- ✓ Generates detailed log file
- ✓ **No root required** - safe read-only analysis

**Detects:**
- Hash configs using `[]` or `()` instead of `{}`
- Array configs using `()` instead of `[]`
- Type mismatches in loaded configuration
- Syntax errors and missing semicolons
- Nested structure corruption

### 2. `backuppc_config_fixer.pl`
**Automated repair tool** that fixes all detected corruption issues.

**Features:**
- ✓ Fixes hash configurations to use `{}`
- ✓ Fixes array configurations to use `[]`
- ✓ Creates timestamped backups before changes
- ✓ Validates syntax after fixes
- ✓ Tests configuration loading (main config)
- ✓ Processes main config and all host configs
- ✓ Generates detailed fix log
- ✓ **Requires root** - modifies system files

**Safety Features:**
- Automatic backup creation
- Syntax validation before saving
- Configuration loading tests
- Rollback capability via backups

## 🚀 Quick Start

### Step 1: Diagnose Issues

Run the diagnostic tool to check for corruption:

```bash
cd backupfile_config_fixer
perl backuppc_config_diagnostic.pl
```

**Expected Output:**
- If issues found: Lists all corruption patterns detected
- If clean: "✓ CONFIGURATION APPEARS HEALTHY"
- Log saved to: `/tmp/backuppc_diagnostic_final.log`

### Step 2: Fix Issues (if needed)

If the diagnostic found issues, run the fix script:

```bash
sudo perl backuppc_config_fixer.pl
```

**What it does:**
1. Processes `/etc/BackupPC/config.pl`
2. Processes all files in `/etc/BackupPC/pc/*.pl`
3. Creates backups with suffix `.backup_<timestamp>`
4. Applies fixes and validates each file
5. Generates detailed log

**Output:**
- Number of files processed and fixed
- Specific fixes applied per file
- Backup file locations
- Next steps for verification

### Step 3: Restart BackupPC

After fixing, restart the service:

```bash
sudo systemctl restart backuppc
```

Wait 10-15 seconds for full startup.

### Step 4: Verify

Test the web interface:

```bash
# Check service status
sudo systemctl status backuppc

# Test web interface
# Navigate to: http://your-hostname/backuppc/

# Check for errors
sudo tail -20 /var/log/apache2/error.log | grep BackupPC
```

Re-run the diagnostic to confirm:

```bash
perl backuppc_config_diagnostic.pl
```

Should show: **✓ CONFIGURATION APPEARS HEALTHY**

## 📋 Detailed Usage

### Diagnostic Script

```bash
# Basic usage
perl backuppc_config_diagnostic.pl

# Review detailed log
cat /tmp/backuppc_diagnostic_final.log

# Check exit code
echo $?
# 0 = no issues, >0 = issues found
```

**Diagnostic Tests:**
1. Configuration file syntax analysis
2. Data::Dumper corruption pattern check
3. BackupPC runtime configuration check
4. Web interface error check
5. Service status check

### Fix Script

```bash
# Must run as root
sudo perl backuppc_config_fixer.pl

# Review fix log
cat /tmp/backuppc_unified_fix.log

# Check what was backed up
ls -lh /etc/BackupPC/*.backup_*
ls -lh /etc/BackupPC/pc/*.backup_*
```

**Fix Process:**
1. Validates root permissions
2. Scans all configuration files
3. Creates backups for files needing fixes
4. Applies fixes:
   - Hash configs: converts `[]` or `()` → `{}`
   - Array configs: converts `()` → `[]`
5. Validates Perl syntax
6. Tests configuration loading
7. Saves fixed files
8. Reports summary

## 🔧 Command Reference

### Common Operations

```bash
# Check if you have corruption
perl backuppc_config_diagnostic.pl

# Fix all issues
sudo perl backuppc_config_fixer.pl

# Restart BackupPC
sudo systemctl restart backuppc

# Monitor logs
sudo tail -f /var/log/apache2/error.log

# Check service status
sudo systemctl status backuppc

# View BackupPC main log
sudo tail -f /var/log/BackupPC/LOG
```

### Backup Management

```bash
# List all backups created by fix script
ls -lh /etc/BackupPC/*.backup_*
ls -lh /etc/BackupPC/pc/*.backup_*

# Restore from backup (if needed)
sudo cp /etc/BackupPC/config.pl.backup_<timestamp> /etc/BackupPC/config.pl

# Remove old backups (after confirming everything works)
sudo rm /etc/BackupPC/*.backup_*
sudo rm /etc/BackupPC/pc/*.backup_*
```

## 📊 Understanding the Output

### Diagnostic Output

```
✓ = No issues / Test passed
✗ = Issues found / Test failed

Files processed:     X
Files with issues:   Y
Total issues found:  Z

Issue Breakdown:
  HASH_AS_ARRAY_MULTILINE: N
  ARRAY_AS_PAREN_INLINE: M
  TYPE_MISMATCH: K
```

### Fix Output

```
Files processed:     X   # Total files scanned
Files fixed:         Y   # Files that had changes
Total fixes applied: Z   # Individual corrections made

Next steps:
1. Restart BackupPC
2. Wait 10-15 seconds
3. Test web interface
4. Verify with diagnostic
```

## 🛡️ Safety & Rollback

### Backup Strategy

The fix script creates timestamped backups before any changes:

```
Original:  /etc/BackupPC/config.pl
Backup:    /etc/BackupPC/config.pl.backup_1727892345
```

### Rolling Back

If something goes wrong:

```bash
# Find the backup timestamp
ls -lh /etc/BackupPC/*.backup_*

# Restore the backup
sudo cp /etc/BackupPC/config.pl.backup_<timestamp> /etc/BackupPC/config.pl

# Restore host configs if needed
sudo cp /etc/BackupPC/pc/hostname.pl.backup_<timestamp> /etc/BackupPC/pc/hostname.pl

# Restart BackupPC
sudo systemctl restart backuppc
```

## 🐛 Troubleshooting

### Issue: Diagnostic shows errors, but fix script finds nothing

**Cause:** Files may have been manually edited or already fixed.

**Solution:** Re-run diagnostic to confirm current state.

### Issue: Fix script fails with "Cannot backup file"

**Cause:** Permission issues or disk space.

**Solution:**
```bash
# Check permissions
ls -la /etc/BackupPC/

# Check disk space
df -h /etc

# Ensure correct ownership
sudo chown -R backuppc:backuppc /etc/BackupPC/
```

### Issue: Web interface still shows errors after fix

**Cause:** BackupPC may not have restarted properly or cache issues.

**Solution:**
```bash
# Force restart
sudo systemctl stop backuppc
sleep 5
sudo systemctl start backuppc

# Clear web cache (if using nginx/apache)
sudo systemctl restart apache2
# or
sudo systemctl restart nginx

# Check for remaining errors
sudo tail -50 /var/log/apache2/error.log | grep BackupPC
```

### Issue: Syntax validation fails

**Cause:** Complex corruption pattern or custom configuration.

**Solution:**
1. Check the backup file
2. Review the specific error in the log
3. Manually inspect the problematic section
4. Contact BackupPC support with log files

## 📁 File Locations

| File | Location | Purpose |
|------|----------|---------|
| Main config | `/etc/BackupPC/config.pl` | Primary BackupPC configuration |
| Host configs | `/etc/BackupPC/pc/*.pl` | Per-host backup configurations |
| Diagnostic log | `/tmp/backuppc_diagnostic_final.log` | Detailed diagnostic results |
| Fix log | `/tmp/backuppc_unified_fix.log` | Detailed fix operations log |
| Backups | `/etc/BackupPC/*.backup_*` | Timestamped backup files |
| Apache errors | `/var/log/apache2/error.log` | Web interface errors |
| BackupPC log | `/var/log/BackupPC/LOG` | BackupPC service log |

## 🔗 Related Issues

- **BackupPC Version:** 4.4.0
- **Perl Version:** 5.38.2
- **Issue:** Data::Dumper serialization behavior change
- **Symptoms:** Web interface errors, "Not a HASH reference" errors
- **GitHub:** https://github.com/backuppc/backuppc/issues

## 📝 Version History

### v1.0 (2025-10-02)
- Initial release
- Unified diagnostic and fix scripts
- Comprehensive pattern detection
- Automatic backup and rollback support
- Syntax validation and loading tests
- Support for main and host configurations

## 👥 Credits

**Author:** GitHub Copilot Assistant  
**Date:** October 2, 2025  
**Status:** Production Ready

## 📄 License

These scripts are provided as-is for fixing BackupPC configuration issues. Use at your own risk. Always maintain backups of your configuration files.

## 🆘 Support

If you encounter issues:

1. **Check logs:** `/tmp/backuppc_diagnostic_final.log` and `/tmp/backuppc_unified_fix.log`
2. **Verify backups exist:** `ls -lh /etc/BackupPC/*.backup_*`
3. **Check Apache/web server logs:** `/var/log/apache2/error.log`
4. **Review BackupPC logs:** `/var/log/BackupPC/LOG`
5. **Consult BackupPC documentation:** https://backuppc.github.io/backuppc/

For persistent issues, consult the BackupPC community or file an issue on the BackupPC GitHub repository.

---

**⚠️ Important:** Always run the diagnostic script first before applying fixes. Always verify backups exist before modifying configuration files. Test in a non-production environment if possible.
