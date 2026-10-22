package com.redhat.demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;

@Path("/archive")
public class ArchiveResource {

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String getArchiveLibraryVersion() {
        Package pkg = TarArchiveInputStream.class.getPackage();
        String version = (pkg != null && pkg.getImplementationVersion() != null)
                ? pkg.getImplementationVersion()
                : "unknown";
        return "Apache Commons Compress (" + TarArchiveInputStream.class.getSimpleName() + ") version: " + version;
    }
}
