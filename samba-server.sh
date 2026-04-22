#!/bin/bash

# ==============================
# SAMBA SERVER MANAGER
# ==============================

export GTK_THEME=Orchis-dark

LOG="/var/log/samba_gui.log"
BACKUP_DIR="/var/backups/samba"
MONITOR_PID_FILE="/tmp/samba_monitor.pid"

# Initialize log file
touch "$LOG" 2>/dev/null

# ==============================
# ROOT PRIVILEGE CHECK
# ==============================
if [[ $EUID -ne 0 ]]; then
    zenity --error --text="Please run this script with sudo (e.g., sudo ./script.sh)"
    exit 1
fi

# ==============================
# HELPER: Get user-defined shares only (exclude [global], [homes], [printers], etc.)
# ==============================
get_user_shares(){
    grep "^\[" /etc/samba/smb.conf \
        | sed 's/\[//;s/\]//' \
        | grep -vE "^(global|homes|printers|print\$|netlogon|sysvol)$"
}

# ==============================
# INSTALLATION
# ==============================
install_all(){
    apt update
    apt install -y samba zenity inotify-tools
    mkdir -p "$BACKUP_DIR"
    mkdir -p "/samba"
    chmod 777 "/samba"
    zenity --info --text="All packages installed and /samba directory prepared."
}

# ==============================
# SHARE MANAGEMENT
# ==============================
configure_share(){
    folder=$(zenity --entry --text="Enter Share Name (letters, numbers, hyphens and underscores only, no spaces)")
    [ -z "$folder" ] && return

    # Validate share name — no spaces or special characters
    if [[ ! "$folder" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        zenity --error --text="Invalid share name. Use only letters, numbers, hyphens, and underscores."
        return
    fi

    # Check if share already exists
    if grep -q "^\[$folder\]" /etc/samba/smb.conf; then
        zenity --error --text="A share named [$folder] already exists!"
        return
    fi

    user_choice=$(zenity --list --title="Access Type" --column="Options" \
        "Public (No Password)" "Private (Password Protected)")
    [ -z "$user_choice" ] && return

    path="/samba/$folder"
    mkdir -p "$path"
    chmod -R 777 "$path"

    if [ "$user_choice" == "Private (Password Protected)" ]; then
        username=$(zenity --entry --text="Enter existing Samba Username to grant access")
        [ -z "$username" ] && { zenity --error --text="Username required!"; return; }

        # Verify user exists in Samba
        if ! pdbedit -L | cut -d: -f1 | grep -qx "$username"; then
            zenity --error --text="Samba user '$username' does not exist. Please add the user first."
            return
        fi

        config_entry="
[$folder]
   path = $path
   writable = yes
   valid users = $username
   guest ok = no"
   else
        config_entry="
[$folder]
   path = $path
   browseable = yes
   writable = yes
   read only = no
   guest ok = yes
   force user = nobody
   force group = nogroup
   create mask = 0777
   directory mask = 0777"
    fi

    echo "$config_entry" >> /etc/samba/smb.conf

    systemctl restart smbd
    zenity --info --text="Share Created: $path\nAccess Type: $user_choice"
}

# ==============================
# SHOW SHARES
# ==============================
show_shares(){
    shares=$(get_user_shares)
    if [ -z "$shares" ]; then
        zenity --info --text="No user-defined shares found."
        return
    fi
    echo "$shares" | zenity --list --title="Samba Shares" --column="Share Names" --width=400 --height=300
}

# ==============================
# DELETE SHARE
# ==============================
delete_share(){
    shares=$(get_user_shares)
    if [ -z "$shares" ]; then
        zenity --info --text="No user-defined shares found to delete."
        return
    fi

    folder=$(echo "$shares" | zenity --list --column="Select Share to Delete" \
        --title="Delete Share" --width=400 --height=300)
    [ -z "$folder" ] && return

    # Safety: prevent deleting system sections
    if [[ "$folder" =~ ^(global|homes|printers|print\$|netlogon|sysvol)$ ]]; then
        zenity --error --text="Cannot delete system section [$folder]."
        return
    fi

    zenity --question --text="Are you sure you want to delete share [$folder] and its files?" || return

    # Backup config before modifying
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

    # Remove the section block from smb.conf using awk
    awk -v section="[$folder]" '
        $0 == section { flag=1; next }
        /^\[/ { flag=0 }
        !flag { print }
    ' /etc/samba/smb.conf > /tmp/smb_new.conf

    # Verify awk produced a non-empty result before overwriting
    if [ -s /tmp/smb_new.conf ]; then
        mv /tmp/smb_new.conf /etc/samba/smb.conf
    else
        zenity --error --text="Error modifying smb.conf. Restoring backup."
        cp /etc/samba/smb.conf.bak /etc/samba/smb.conf
        return
    fi

    # Remove the share directory if it exists under /samba
    share_path=$(grep -A5 "^\[$folder\]" /etc/samba/smb.conf.bak | grep "path" | awk '{print $3}')
    if [ -n "$share_path" ] && [[ "$share_path" == /samba/* ]]; then
        rm -rf "$share_path"
    fi

    systemctl restart smbd
    zenity --info --text="Share [$folder] deleted successfully."
}

# ==============================
# USER MANAGEMENT
# ==============================
add_user(){
    u=$(zenity --entry --text="Enter new username")
    [ -z "$u" ] && return

    # Validate username
    if [[ ! "$u" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        zenity --error --text="Invalid username. Use only letters, numbers, hyphens, and underscores."
        return
    fi

    p=$(zenity --password --text="Enter password for '$u'")
    [ -z "$p" ] && { zenity --error --text="Password cannot be empty."; return; }

    # Add system user only if it doesn't already exist
    if ! id "$u" &>/dev/null; then
        adduser --disabled-password --gecos "" "$u"
        if [ $? -ne 0 ]; then
            zenity --error --text="Failed to create system user '$u'."
            return
        fi
    fi

    # Add/update Samba password
    echo -e "$p\n$p" | smbpasswd -s -a "$u"
    if [ $? -eq 0 ]; then
        zenity --info --text="Samba user '$u' added/updated successfully."
    else
        zenity --error --text="Failed to set Samba password for '$u'."
    fi
}

delete_user(){
    users=$(pdbedit -L 2>/dev/null | cut -d: -f1)
    if [ -z "$users" ]; then
        zenity --info --text="No Samba users found."
        return
    fi

    u=$(echo "$users" | zenity --list --column="Samba Users" --title="Select User to Delete")
    [ -z "$u" ] && return

    zenity --question --text="Are you sure you want to delete Samba user '$u'?\n\nThis will also remove the system account." || return

    smbpasswd -x "$u"
    if id "$u" &>/dev/null; then
        deluser --remove-home "$u"
    fi
    zenity --info --text="User '$u' removed."
}

list_users(){
    users=$(pdbedit -L 2>/dev/null)
    if [ -z "$users" ]; then
        zenity --info --text="No Samba users found." --title="Samba User List"
    else
        zenity --info --text="$users" --title="Samba User List" --width=400 --height=300
    fi
}

# ==============================
# SERVICE CONTROL
# ==============================
start_service(){
    systemctl start smbd
    [ $? -eq 0 ] && zenity --info --text="Samba service started." \
                  || zenity --error --text="Failed to start Samba service."
}

stop_service(){
    systemctl stop smbd
    [ $? -eq 0 ] && zenity --info --text="Samba service stopped." \
                  || zenity --error --text="Failed to stop Samba service."
}

restart_service(){
    systemctl restart smbd
    [ $? -eq 0 ] && zenity --info --text="Samba service restarted." \
                  || zenity --error --text="Failed to restart Samba service."
}

# ==============================
# MONITORING + AUTO BACKUP
# ==============================
start_monitor(){
    # Check if monitor is already running
    if [ -f "$MONITOR_PID_FILE" ]; then
        old_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            zenity --warning --text="Auto-Backup Monitor is already running (PID: $old_pid).\nStop it first before starting a new one."
            return
        else
            rm -f "$MONITOR_PID_FILE"
        fi
    fi

    folder_path=$(zenity --file-selection --directory --title="Select Folder to Monitor")
    [ -z "$folder_path" ] && return

    (
        inotifywait -m -r -e modify,create,delete "$folder_path" 2>/dev/null \
        | while read -r d a f; do
            ts=$(date +%s)
            bname=$(basename "$folder_path")
            backup_file="auto_${bname}_${ts}.tar.gz"

            tar -czf "$BACKUP_DIR/$backup_file" "$folder_path" 2>/dev/null

            echo "$(date '+%Y-%m-%d %H:%M:%S') | $bname | $backup_file | Event: $a$f" >> "$LOG"
        done
    ) &

    monitor_pid=$!
    echo "$monitor_pid" > "$MONITOR_PID_FILE"
    zenity --info --text="Auto-Backup Monitoring started (PID: $monitor_pid).\nFolder: $folder_path\nBackups saved to: $BACKUP_DIR"
}

stop_monitor(){
    if [ ! -f "$MONITOR_PID_FILE" ]; then
        zenity --info --text="No active monitor found."
        return
    fi

    pid=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" && rm -f "$MONITOR_PID_FILE"
        zenity --info --text="Auto-Backup Monitor stopped (PID: $pid)."
    else
        rm -f "$MONITOR_PID_FILE"
        zenity --info --text="Monitor process was not running. PID file cleaned up."
    fi
}

# ==============================
# BACKUP: VIEW FILES
# ==============================
view_backup_files(){
    files=$(ls "$BACKUP_DIR" 2>/dev/null)
    if [ -z "$files" ]; then
        zenity --info --text="No backup files found in $BACKUP_DIR."
        return
    fi
    echo "$files" | zenity --list --column="Available Backups" --title="Backup Files" --width=500 --height=400
}

# ==============================
# BACKUP MANAGER
# ==============================
backup_manager(){
    files=$(ls "$BACKUP_DIR" 2>/dev/null)
    if [ -z "$files" ]; then
        zenity --info --text="No backup files found in $BACKUP_DIR."
        return
    fi

    f=$(echo "$files" | zenity --list --column="Backup Files" --title="Select Backup to Manage" --width=500 --height=400)
    [ -z "$f" ] && return

    action=$(zenity --list --title="Action" --column="Options" "View Content" "Restore to Folder")
    [ -z "$action" ] && return

    if [ "$action" == "View Content" ]; then
        content=$(tar -tzf "$BACKUP_DIR/$f" 2>&1)
        if [ $? -eq 0 ]; then
            echo "$content" | zenity --text-info --title="Contents of $f" --width=600 --height=400
        else
            zenity --error --text="Failed to read backup file: $f"
        fi

    elif [ "$action" == "Restore to Folder" ]; then
        dest=$(zenity --file-selection --directory --title="Select Restore Destination")
        [ -z "$dest" ] && return

        # Use --strip-components=1 or absolute path stripping to avoid restoring to original root path
        tar -xzf "$BACKUP_DIR/$f" --strip-components=1 -C "$dest" 2>/dev/null
        if [ $? -eq 0 ]; then
            chmod -R 777 "$dest"
            zenity --info --text="Files restored to: $dest"
        else
            # Fallback: try without strip
            tar -xzf "$BACKUP_DIR/$f" -C "$dest" 2>/dev/null
            chmod -R 777 "$dest"
            zenity --info --text="Files restored to: $dest (full path preserved)"
        fi
    fi
}

# ==============================
# VIEW LOG
# ==============================
view_log(){
    if [ ! -s "$LOG" ]; then
        zenity --info --text="Log file is empty."
        return
    fi
    zenity --text-info --filename="$LOG" --title="Samba Activity Log" --width=700 --height=500
}

# ==============================
# MAIN MENU
# ==============================
while true; do
    choice=$(zenity --list \
        --title="SAMBA SERVER MANAGER" \
        --width=480 --height=650 \
        --column="Options" \
        "1  Install All" \
        "2  Create Share" \
        "3  Show Shares" \
        "4  Delete Share" \
        "5  Add User" \
        "6  Delete User" \
        "7  List Users" \
        "8  Start Service" \
        "9  Stop Service" \
        "10 Restart Service" \
        "11 Monitor + Auto Backup (Start)" \
        "12 Monitor + Auto Backup (Stop)" \
        "13 View Backup Files" \
        "14 Backup Manager" \
        "15 View Activity Log" \
        "0  Exit")

    case $choice in
        "1  Install All")                    install_all ;;
        "2  Create Share")                   configure_share ;;
        "3  Show Shares")                    show_shares ;;
        "4  Delete Share")                   delete_share ;;
        "5  Add User")                       add_user ;;
        "6  Delete User")                    delete_user ;;
        "7  List Users")                     list_users ;;
        "8  Start Service")                  start_service ;;
        "9  Stop Service")                   stop_service ;;
        "10 Restart Service")                restart_service ;;
        "11 Monitor + Auto Backup (Start)")  start_monitor ;;
        "12 Monitor + Auto Backup (Stop)")   stop_monitor ;;
        "13 View Backup Files")              view_backup_files ;;
        "14 Backup Manager")                 backup_manager ;;
        "15 View Activity Log")              view_log ;;
        "0  Exit")                           exit 0 ;;
        *)                                   exit 0 ;;
    esac
done
