#!/bin/sh

### USAGE
usage(){
    echo -e "\n\n"
    echo "USAGE:  $(basename $0) -s /path/to/source/vmdk -d /path/to/new/vm [-n X] [-m Y] [-f] [-q] "
    echo "          [-h]"
    echo 
    echo "    where:"
    echo "        -s  - Source drive.  Path to source vmx file.  VMX must be linked to a snapshot"
    echo "              for this to work"
    echo "        -d  - Destination.  Directory that should be created to house the new "
    echo "              vm files"
    echo "        -n  - Number of network interfaces (1-10).  Optional argument.  Default is to "
    echo "              not change number specified in vmx file."
    echo "        -m  - Amount of memory allocated to machine in megabytes.  Use G "
    echo "              suffix to specify gigabytes.  Optional argument.  Default is to not to"
    echo "              change amount defined in vmx file." 
    echo "        -f  - Force cloning.  Bypasses user prompts, for use with scripting.  Optional"
    echo "              argument."
    echo "        -q  - Quiet.  Outputs only vmid of vmcreated.  Useful for scripting.  Implies -f."
    echo "        -h  - Help.  this usage statement."
    echo -e "\n\n"
}

error(){
    echo -e "\n$@"
    usage
    exit 1
}

message(){
    if [ "x$QUIET" = "x" ]; then echo -e "$@"; fi
}    

### PARSE COMMAND LINE OPTIONS
OPTIND=1;

while getopts "qfs:d:n:m:h" opt; do

    case "$opt" in
    
        s)
            SOURCE_VMX=$OPTARG
            ;;
        d)  
            VM_DIR=$OPTARG
            ;;
        n)
            NIC_COUNT=$OPTARG
            ;;
        m)
            MEMORY=$OPTARG
            ;;
        h)  
            usage
            exit 0
            ;;
        f)
            AUTO="YES"
            ;;
        q)
            AUTO="YES"
            QUIET="YeS"
            ;;
        '?')
            usage >&2
            exit 1
            ;;
    esac
 
done


### CHECK OPTIONS

if [ "x$SOURCE_VMX" = "x" ]; then

    error "ERROR:  No source VMX provided.  Please specify one using the -s option"

elif ! $(echo $SOURCE_VMX | grep -qie"\.vmx$") ; then

    error "ERROR:  Source disk is not a vmx.  Please specify a vmx file using the -s option."
    
elif [ ! -e "$SOURCE_VMX" ]; then

    error "ERROR:  Source disk provided does not exist.  Please specify an existing VMX using \n"\
           "       the -s option"

fi

SOURCE_VMDK="$(grep $(grep hardDisk "$SOURCE_VMX"|cut -d. -f1).fileName "$SOURCE_VMX" |cut -d '"' -f 2)"
SOURCE_VMDK_DELTA="$(echo $SOURCE_VMDK|awk '{print substr($0,1,length($0)-5)}')-delta.vmdk"
SOURCE_DIR="$(dirname "$SOURCE_VMX")" 
VOL_SYM_LINK="$(dirname "$(grep sched.swap.derivedName "$SOURCE_VMX"|cut -d'"' -f 2)"|cut -d/ -f 4)"
SOURCE_DIR="$(echo "$SOURCE_DIR"|sed "s/\/$(echo $SOURCE_DIR|cut -d/ -f4)\//\/$VOL_SYM_LINK\//g")"

SOURCE_VMX="$(echo "$SOURCE_VMX"|sed "s/\/$(echo $SOURCE_VMX|cut -d/ -f4)\//\/$VOL_SYM_LINK\//g")"

if [ "$SOURCE_VMDK" = "$(basename "$SOURCE_VMDK")" ]; then
    SOURCE_VMDK="$SOURCE_DIR/$SOURCE_VMDK"
    SOURCE_VMDK_DELTA="$SOURCE_DIR/$SOURCE_VMDK_DELTA"
fi

if [ ! -e "$SOURCE_VMDK" ]; then

    error  "ERROR:  Source vmx does not reference a real source virtual disk (VMDK).  \n"\
            "       Please specify a corectly constructed VMX file using the -s option."
       
elif [ "x$(echo $SOURCE_VMDK|grep -e "-[0-9][0-9][0-9][0-9][0-9][0-9].vmdk")" = "x" ]; then

    error "ERROR:  Source vmx does not reference a snapshoted virtual disk.  Please specify\n"\
           "       a snapshoted vmx using the -s option."

elif [ ! -e "$SOURCE_VMDK_DELTA" ]; then

    error "ERROR:  Snapshot delta file does not exist.  Please specify a vmx with a proper \n"\
           "       snapshot using the -s option."
    
fi

BASE_VMDK="$(grep parentFileNameHint "$SOURCE_VMDK"|cut -d'"' -f2)"
BASE_VMDK_FLATFILE="$(echo $BASE_VMDK|awk '{print substr($0,1,length($0)-5)}')-flat.vmdk"
if [ "$BASE_VMDK" = "$(basename "$BASE_VMDK")" ]; then
    BASE_VMDK="$SOURCE_DIR/$BASE_VMDK"
    BASE_VMDK_FLATFILE="$SOURCE_DIR/$BASE_VMDK_FLATFILE"
fi

if [ ! -e "$BASE_VMDK" ]; then

    error "ERROR:  Base virtual drive does not exist.  Please specify a vmx file describing\n"\
           "       a complete VM using the -s option."
    
elif [ ! -e "$BASE_VMDK_FLATFILE" ]; then

    error "ERROR:  Base virtual drive flatfile does not exist.  Please specify a vmx file\n"\
           "       describing a complete VM using the -s option."

fi

if [ "x$VM_DIR" = "x" ]; then                                              
                                                                                
    error "ERROR:  No destination directory provided.  Please specify one using the -d \n"\
           "        option"
                                                                                                                                                                            
elif [ -e "$VM_DIR" ]; then                                              
                                                                                                                                                                                                                                                                                                                                                                                                                                        
    error "ERROR:  Destination directory exists (can't create a new VM in this location). \n"\
           "       Please specify a nonexistent directory using the -d option."
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    
fi

if [ "x$NIC_COUNT" != "x" ]; then
    if [ $(( $NIC_COUNT + 100 )) -lt 101 ] || [ $(( $NIC_COUNT + 100 )) -gt 110 ]; then

        error "ERROR:  Number of network interfaces is not between 1 and 10.  Please specify \n"\
               "       using the -n option (or omit for the default of 1)."
    fi
fi

if [ "x$MEMORY" != "x" ]; then
    if $(echo $MEMORY | grep -qe 'G$'); then
    
        MEMORY=$(( $(echo $MEMORY |grep -oe '[0-9]*') * 1024 ))

    fi

    MEMORY=$(echo $MEMORY|grep -oe '[0-9]*')

    if [ $(( $MEMORY + 0 )) -lt 1 ]; then
 
        error "ERROR:  At least 1 MB must be specified for the VM (and probably much more).\n"\
               "       Please specify an amount of memory using the -m option (or omit for\n"\
               "       for the default of 1GB"

    fi
fi  


### PRINT VALUES
message "\n\n"
message "Cloning VM with the following values:"
message "    Source drive                 = $SOURCE_VMDK"
message "    New VM path                  = $VM_DIR"
if [ "x$NIC_COUNT" != "x" ]; then 
    message "    Number of Network Interfaces = $NIC_COUNT"
fi 
if [ "x$MEMORY" != "x" ]; then
    message "    Memory allocated to VM       = $MEMORY MB"
fi
message

if [ "x$AUTO" = "x" ]; then
    echo "Press ENTER to start the cloning process"
    read
fi
        

#### START THE CLONING PROCESS
 
#1) Create VM directory 
message "STEP 1.  Create the destination directory..."
mkdir "$VM_DIR"
message "   ...done"
message

#2) Copy target files to new VM
message "STEP 2.  Copy target files from source to new VM..."

cp "$SOURCE_VMX" "$VM_DIR/"
cp "$SOURCE_VMDK" "$VM_DIR/"
cp "$SOURCE_VMDK_DELTA" "$VM_DIR/"


message "   ...done"
message

SOURCE_VMX="$(basename "$SOURCE_VMX")"
SOURCE_VMDK="$(basename "$SOURCE_VMDK")"

#3) Point snapshot VMDK at base disk image 
message "STEP 3.  Point snapshot VMDK at base disk image..."

cp "$VM_DIR/$SOURCE_VMDK" "$VM_DIR/$SOURCE_VMDK.bak"
cat "$VM_DIR/$SOURCE_VMDK.bak"|sed "s|\"$(basename "$BASE_VMDK")\"|\"$BASE_VMDK\"|g">"$VM_DIR/$SOURCE_VMDK"

message "    ...done"
message

#4) Add memory to the VM                                                                              
message "STEP 4.  Configure VM memory..."                                                                   

if [ "x$MEMORY" = "x" ]; then
    message "...bypassed (leaving default memory configuration)."
else
    cat "$VM_DIR/$SOURCE_VMX"|grep -v memSize > "$VM_DIR/$SOURCE_VMX.tmp"                       
    echo "memSize = \"$MEMORY\"" >> "$VM_DIR/$SOURCE_VMX.tmp"                                        
    mv "$VM_DIR/$SOURCE_VMX.tmp" "$VM_DIR/$SOURCE_VMX"                                          
    message  "   ...done"   
fi
message


#5) Changing display name
message "STEP 5.  Changing VM display name to match directory name..."

cat "$VM_DIR/$SOURCE_VMX"|sed "s/displayName = \".*\"/displayName = \"$(basename $VM_DIR)\"/g" > "$VM_DIR/$SOURCE_VMX.tmp"
mv "$VM_DIR/$SOURCE_VMX.tmp" "$VM_DIR/$SOURCE_VMX"

message "   ...done"
message


#6) Registering VM
message STEP 6.  Register VM with system...

if [ "x$QUIET" = "x" ]; then
    echo -n "VM_ID="
fi

VM_ID="$(vim-cmd solo/register "$VM_DIR/$SOURCE_VMX")"
echo $VM_ID

message "   ...done"
message


#7) Add NICs.  Get unit ID by picking unused number.  Existing numbers are found with 
#    vim-cmd vmsvc/device.getdevices 7 | grep unitNumber
message "STEP 7.  Add Network interfaces..."
if [ "x$NIC_COUNT" = "x" ]; then
    message "...bypassed (leaving default network configuration)."
    message
else
    EXISTING_NIC_COUNT="$(grep -oE 'ethernet[0-9]{1,2}' "$VM_DIR/$SOURCE_VMX"|sort|uniq|wc -l)"
    
    if [ $EXISTING_NIC_COUNT -lt $NIC_COUNT ]; then
        export INTERFACE_NUMBER=0
        for COUNTER in $(seq $(($EXISTING_NIC_COUNT + 1)) $NIC_COUNT); do
            export DEVICE_LIST=" $(vim-cmd vmsvc/device.getdevices $VM_ID|grep unitNumber|grep -oe '[0-9]*'|xargs) "
            INTERFACE_NUMBER=$(( $INTERFACE_NUMBER + 1 ))
            echo "$DEVICE_LIST" |grep -q " $INTERFACE_NUMBER "
            while [ $? -eq 0 ]; do 
                INTERFACE_NUMBER=$(( $INTERFACE_NUMBER + 1 ))
                echo "$DEVICE_LIST" |grep -q " $INTERFACE_NUMBER " 
            done
            message "  - Adding interface $COUNTER as device $INTERFACE_NUMBER"
            vim-cmd vmsvc/devices.createnic $VM_ID $INTERFACE_NUMBER "e1000" "VM Network" 2>/dev/null
        done
        message "    ...done"
        message 
    elif [ $EXISTING_NIC_COUNT -eq $NIC_COUNT ]; then
        message "   ...nothing done (number of requested interfaces equals current number of"\
                "interfaces"
        message
    else
        for int in $(grep -oE 'ethernet[0-9]{1,2}' "$VM_DIR/$SOURCE_VMX"|sort|uniq|tail -$(( $EXISTING_NIC_COUNT - $NIC_COUNT ))); do
            message "deleting interface $int"
            grep -v "$int" "$VM_DIR/$SOURCE_VMX" > "$VM_DIR/$SOURCE_VMX.tmp"
            mv "$VM_DIR/$SOURCE_VMX.tmp" "$VM_DIR/$SOURCE_VMX"
        done
        
        vim-cmd vmsvc/reload $VM_ID       
        message "   ...done"
        message
    fi
fi

message "\n\n"
message "Process complete.  Assuming everything worked, you should now have a working clone.  Enjoy"
message "\n\n"
