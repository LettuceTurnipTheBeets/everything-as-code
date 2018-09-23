package com.mindgeek.devops;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;

import com.atlassian.bamboo.specs.api.BambooSpec;
import com.atlassian.bamboo.specs.api.builders.BambooKey;
import com.atlassian.bamboo.specs.api.builders.BambooOid;
import com.atlassian.bamboo.specs.api.builders.Variable;
import com.atlassian.bamboo.specs.api.builders.deployment.Deployment;
import com.atlassian.bamboo.specs.api.builders.deployment.Environment;
import com.atlassian.bamboo.specs.api.builders.deployment.ReleaseNaming;
import com.atlassian.bamboo.specs.api.builders.notification.Notification;
import com.atlassian.bamboo.specs.api.builders.permission.DeploymentPermissions;
import com.atlassian.bamboo.specs.api.builders.permission.EnvironmentPermissions;
import com.atlassian.bamboo.specs.api.builders.permission.PermissionType;
import com.atlassian.bamboo.specs.api.builders.permission.Permissions;
import com.atlassian.bamboo.specs.api.builders.permission.PlanPermissions;
import com.atlassian.bamboo.specs.api.builders.plan.Job;
import com.atlassian.bamboo.specs.api.builders.plan.Plan;
import com.atlassian.bamboo.specs.api.builders.plan.PlanIdentifier;
import com.atlassian.bamboo.specs.api.builders.plan.Stage;
import com.atlassian.bamboo.specs.api.builders.plan.artifact.Artifact;
import com.atlassian.bamboo.specs.api.builders.plan.branches.BranchCleanup;
import com.atlassian.bamboo.specs.api.builders.plan.branches.PlanBranchManagement;
import com.atlassian.bamboo.specs.api.builders.plan.configuration.AllOtherPluginsConfiguration;
import com.atlassian.bamboo.specs.api.builders.plan.configuration.ConcurrentBuilds;
import com.atlassian.bamboo.specs.api.builders.project.Project;
import com.atlassian.bamboo.specs.api.builders.repository.VcsRepositoryIdentifier;
import com.atlassian.bamboo.specs.builders.notification.DeploymentFinishedNotification;
import com.atlassian.bamboo.specs.builders.notification.EmailRecipient;
import com.atlassian.bamboo.specs.builders.notification.PlanStatusChangedNotification;
import com.atlassian.bamboo.specs.builders.notification.UserRecipient;
import com.atlassian.bamboo.specs.builders.notification.XFailedChainsNotification;
import com.atlassian.bamboo.specs.builders.task.ArtifactDownloaderTask;
import com.atlassian.bamboo.specs.builders.task.CheckoutItem;
import com.atlassian.bamboo.specs.builders.task.CleanWorkingDirectoryTask;
import com.atlassian.bamboo.specs.builders.task.DockerRunContainerTask;
import com.atlassian.bamboo.specs.builders.task.DownloadItem;
import com.atlassian.bamboo.specs.builders.task.ScriptTask;
import com.atlassian.bamboo.specs.builders.task.VcsCheckoutTask;
import com.atlassian.bamboo.specs.builders.trigger.RemoteTrigger;
import com.atlassian.bamboo.specs.model.task.ScriptTaskProperties;
import com.atlassian.bamboo.specs.util.BambooServer;
import com.atlassian.bamboo.specs.util.MapBuilder;

@BambooSpec
public class ExampleTemplate {

    public final String PROJECTKEY = "DOT";
    public final String PROJECTNAME = "DevOps";

    public final String PLANKEY = "TPEX";
    public final String PLANNAME = "Template Example";
    public final String DEPLOYMENTPLANNAME = PROJECTNAME + " - " + PLANNAME;
    public final String LINKED_REPOSITORY_NAME = "Template Example";

    public final String ADMINNAME = "j_smith";
    public final String NOTIFICATIONEMAIL = "john.smith@mindgeek.com";

    public final boolean ENABLE_BITBUCKET_SSH_KEY = false;
    public final boolean ENABLE_RSYNC_SSH_KEY = false;

    public final String HIPCHAT_ROOM = "";
    public final String HIPCHAT_TOKEN = "";

    public static final int NUMBER_OF_STAGES = 1;
    public final String RSYNC_ENCRYPTED_PRIVATE_SSH_KEY = "";

    public ArrayList<String> getUserPermissions(String type) {
        ArrayList<String> listOfUsers = new ArrayList<String>();

        if (type == "build") {
            // If user is in deploy_prod he is auto in build
            // Add in this group people who should have build only perm and no deployment perms
            ArrayList<String> users = this.getUserPermissions("deploy_stage");
            listOfUsers.addAll(users);
        }

        if (type == "deploy_stage") {
            // If user is in deploy_prod he is auto in deploy_stage
            // Add in this group people who should have stage deployement permission but not prod
            ArrayList<String> users = this.getUserPermissions("deploy_prod");
            listOfUsers.addAll(users);
        }

        if (type == "deploy_prod") {
            listOfUsers.add(ADMINNAME);
        }

        return listOfUsers;
    }

    static String readFile(String path, Charset encoding) throws IOException {
        byte[] encoded = Files.readAllBytes(Paths.get(path));
        return new String(encoded, encoding);
    }

    public Plan plan() {
        final String COMPRESSIONSCRIPT = AuthApiMesos.readFile("src/main/java/com/mindgeek/bamboo-scripts/compress-sources.sh", Charset.defaultCharset());

        final Plan plan = new Plan(
                new Project().key(new BambooKey(PROJECTKEY)).name(PROJECTNAME),
                PLANNAME,
                new BambooKey(PLANKEY))
            .description("Managed by BambooSPECS")
            .pluginConfigurations(new ConcurrentBuilds()
                    .useSystemWideDefault(false),
                new AllOtherPluginsConfiguration()
                    .configuration(new MapBuilder()
                            .put("custom.buildExpiryConfig", new MapBuilder()
                                .put("duration", "20")
                                .put("period", "days")
                                .put("labelsToKeep", "")
                                .put("buildsToKeep", "3")
                                .put("enabled", "false")
                                .put("expiryTypeArtifact", "true")
                                .build())
                            .build()))
            .stages(new Stage("Default Stage")
                    .jobs(new Job("Make Build artifact",
                            new BambooKey("BA"))
                            .description("Managed by BambooSPECS")
                            .pluginConfigurations(new AllOtherPluginsConfiguration()
                                    .configuration(new MapBuilder()
                                            .put("custom", new MapBuilder()
                                                .put("auto", new MapBuilder()
                                                    .put("regex", "")
                                                    .put("label", "")
                                                    .build())
                                                .put("buildHangingConfig.enabled", "false")
                                                .build())
                                            .build()))
                            .artifacts(new Artifact()
                                    .name("Project sources")
                                    .copyPattern("sources.tar.zst")
                                    .shared(true),
                                new Artifact()
                                    .name("Makefile")
                                    .copyPattern("Makefile*")
                                    .shared(true))
                            .tasks(new CleanWorkingDirectoryTask(),
                                new ScriptTask()
                                    .description("Create tracking file")
                                    .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                                    .inlineBody("#!/usr/bin/env bash\n\nset -x;\ntouch tracking.tmp;"),
                                new VcsCheckoutTask()
                                    .description("Checkout Default Repository")
                                    .checkoutItems(new CheckoutItem().defaultRepository()),
                                new ScriptTask()
                                    .description("Bamboo private key and known_hosts")
                                    .enabled(ENABLE_BITBUCKET_SSH_KEY)
                                    .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                                    .inlineBody("#!/usr/bin/env bash\n\nmkdir -p ${bamboo.working.directory}/.ssh\necho \"${bamboo.GLOBAL_RO_STASH_PASSWORD}\" > ${bamboo.working.directory}/.ssh/id_rsa\n\nchmod 600 ${bamboo.working.directory}/.ssh/id_rsa\nssh-keyscan -p 7999 stash.mgcorp.co > ${bamboo.working.directory}/.ssh/known_hosts\nssh-keygen -Hf ${bamboo.working.directory}/.ssh/known_hosts"),
                                new ScriptTask()
                                    .description("Build code")
                                    .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                                    .inlineBody("#!/usr/bin/env bash\n\nmake build")
                                    .environmentVariables("REVISION=\"${bamboo.planRepository.revision}\" BAMBOO_WORKING_DIRECTORY=\"${bamboo.working.directory}\""),
                                new ScriptTask()
                                    .description("Compress source folder to artifact")
                                    .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                                    .inlineBody(COMPRESSIONSCRIPT)
                                new ScriptTask()
                                    .description("Remove tracking file")
                                    .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                                    .inlineBody("#!/usr/bin/env bash\n\nset -x;\nrm -rf tracking.tmp"))
                            .finalTasks()
                            .cleanWorkingDirectory(true)))
            .linkedRepositories(LINKED_REPOSITORY_NAME)
            .triggers(new RemoteTrigger())
            .planBranchManagement(new PlanBranchManagement()
                    .createManually()
                    .delete(new BranchCleanup()
                        .whenRemovedFromRepositoryAfterDays(3)
                        .whenInactiveInRepositoryAfterDays(10))
                    .notificationLikeParentPlan())
            .notifications(new Notification()
                    .type(new XFailedChainsNotification()
                            .numberOfFailures(3))
                    .recipients(new EmailRecipient(NOTIFICATIONEMAIL)),
                new Notification()
                    .type(new PlanStatusChangedNotification())
                    .recipients(new EmailRecipient(NOTIFICATIONEMAIL)));
        return plan;
    }

    public PlanPermissions planPermission() {

        Permissions perms = new Permissions().loggedInUserPermissions(PermissionType.VIEW);
        ArrayList<String> listOfUsers = this.getUserPermissions("build");
        for (String userName : listOfUsers) {
            perms.userPermissions(userName, PermissionType.VIEW, PermissionType.BUILD);
        }

        PlanPermissions planPermission = new PlanPermissions(new PlanIdentifier(PROJECTKEY, PLANKEY))
            .permissions(perms);

        return planPermission;
    }

    public Deployment rootObject() throws IOException {
        final String DEPLOYMENTSCRIPT = AuthApiMesos.readFile("src/main/java/com/mindgeek/bamboo-scripts/marathon-deployment.sh", Charset.defaultCharset());
        final String NOTIFICATIONSCRIPT = AuthApiMesos.readFile("src/main/java/com/mindgeek/bamboo-scripts/hipchat-notification.sh", Charset.defaultCharset());

        Deployment rootObject = new Deployment(new PlanIdentifier(PROJECTKEY, PLANKEY), DEPLOYMENTPLANNAME)
            .releaseNaming(new ReleaseNaming("release-1")
                    .autoIncrement(true));

        for (int x = 1; x <= NUMBER_OF_STAGES; x++)
        {
            rootObject.environments(new Environment("Stage " + x)
                    .tasks(new CleanWorkingDirectoryTask(),
                        new ScriptTask()
                            .description("Create tracking file")
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody("#!/usr/bin/env bash\n\nset -x;\ntouch tracking.tmp;"),
                        new ArtifactDownloaderTask()
                            .description("Download release contents")
                            .artifacts(new DownloadItem().allArtifacts(true)),
                        new ScriptTask()
                            .description("SSH Key")
                            .enabled(ENABLE_RSYNC_SSH_KEY)
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody("#!/usr/bin/env bash\n\nmkdir -p ${bamboo.working.directory}/.ssh\necho \"${bamboo.RSYNC_PASSWORD}\" > ${bamboo.working.directory}/.ssh/id_rsa\n\nchmod 600 ${bamboo.working.directory}/.ssh/id_rsa"),
                        new ScriptTask()
                            .description("Deploy")
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                             .inlineBody("#!/usr/bin/env bash\n\nmake deploy")
                            .environmentVariables("WORK_ENV=\"${bamboo.work_env}\" STAGE_NUMBER=\"${bamboo.stage_number}\" BAMBOO_WORKING_DIRECTORY=\"${bamboo.working.directory}\""),
                        new ScriptTask()
                            .description("Remove tracking file")
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody("#!/usr/bin/env bash\n\nset -x;\nrm -rf tracking.tmp"))
                    .finalTasks(new ScriptTask()
                            .description("Send HipChat Notification")
                            .enabled(true)
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody(NOTIFICATIONSCRIPT),
                        new CleanWorkingDirectoryTask())
                    .variables(
                        new Variable("RSYNC_PASSWORD", RSYNC_ENCRYPTED_PRIVATE_SSH_KEY),
                        new Variable("work_env", "stage"),
                        new Variable("stage_number", "" + x),
                        new Variable("hipchat_channel", HIPCHAT_ROOM),
                        new Variable("hipchat_token", HIPCHAT_TOKEN)
                    )
                    .notifications(new Notification()
                            .type(new DeploymentFinishedNotification())
                            .recipients(new EmailRecipient(NOTIFICATIONEMAIL))));
        }

        rootObject.environments(new Environment("Production")
                    .tasks(new CleanWorkingDirectoryTask(),
                        new ScriptTask()
                            .description("Create tracking file")
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody("set -x;\ntouch tracking.tmp;"),
                        new ArtifactDownloaderTask()
                            .description("Download release contents")
                            .artifacts(new DownloadItem().allArtifacts(true)),
                        new ScriptTask()
                            .description("Deployment")
                            .inlineBody(DEPLOYMENTSCRIPT),
                        new ScriptTask()
                            .description("Remove tracking file")
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody("#!/usr/bin/env bash\n\nset -x;\nrm -rf tracking.tmp"))
                    .finalTasks(new ScriptTask()
                            .description("Send HipChat Notification")
                            .enabled(true)
                            .interpreter(ScriptTaskProperties.Interpreter.BINSH_OR_CMDEXE)
                            .inlineBody(NOTIFICATIONSCRIPT),
                        new CleanWorkingDirectoryTask())
                    .variables(new Variable("RSYNC_PASSWORD", RSYNC_ENCRYPTED_PRIVATE_SSH_KEY),
                        new Variable("work_env", "prod"),
                        new Variable("hipchat_channel", HIPCHAT_ROOM),
                        new Variable("hipchat_token", HIPCHAT_TOKEN))
                    .notifications(new Notification()
                            .type(new DeploymentFinishedNotification())
                            .recipients(new EmailRecipient(NOTIFICATIONEMAIL))));

        return rootObject;
    }

    public DeploymentPermissions deploymentPermission() {
        Permissions perms = new Permissions().loggedInUserPermissions(PermissionType.VIEW);
        ArrayList<String> listOfUsers = this.getUserPermissions("deploy_stage");
        for (String userName : listOfUsers) {
            perms.userPermissions(userName, PermissionType.VIEW);
        }

        DeploymentPermissions planPermission = new DeploymentPermissions(DEPLOYMENTPLANNAME)
            .permissions(perms);

        return planPermission;
    }

    public EnvironmentPermissions environmentPermissionStage(int x) {
        Permissions perms = new Permissions().loggedInUserPermissions(PermissionType.VIEW);
        ArrayList<String> listOfUsers = this.getUserPermissions("deploy_stage");
        for (String userName : listOfUsers) {
            perms.userPermissions(userName, PermissionType.VIEW, PermissionType.BUILD);
        }

        EnvironmentPermissions planPermission = new EnvironmentPermissions(DEPLOYMENTPLANNAME)
            .environmentName("Stage " + x)
            .permissions(perms);

        return planPermission;
    }

    public EnvironmentPermissions environmentPermissionProduction() {
        Permissions perms = new Permissions().loggedInUserPermissions(PermissionType.VIEW);
        ArrayList<String> listOfUsers = this.getUserPermissions("deploy_prod");
        for (String userName : listOfUsers) {
            perms.userPermissions(userName, PermissionType.VIEW, PermissionType.BUILD);
        }

        EnvironmentPermissions planPermission = new EnvironmentPermissions(DEPLOYMENTPLANNAME)
            .environmentName("Production")
            .permissions(perms);

        return planPermission;
    }

    public static void main(String... argv) {
        //By default credentials are read from the '.credentials' file.
        BambooServer bambooServer = new BambooServer("http://bamboo.mgcorp.co");
        final ExampleTemplate planSpec = new ExampleTemplate();

        final Plan plan = planSpec.plan();
        bambooServer.publish(plan);

        final PlanPermissions planPermission = planSpec.planPermission();
        bambooServer.publish(planPermission);

        final Deployment rootObject = planSpec.rootObject();
        bambooServer.publish(rootObject);

        final DeploymentPermissions deploymentPermission = planSpec.deploymentPermission();
        bambooServer.publish(deploymentPermission);

        for (int x = 1; x <= ExampleTemplate.NUMBER_OF_STAGES; x++)
        {
            final EnvironmentPermissions environmentPermissionStage = planSpec.environmentPermissionStage(x);
            bambooServer.publish(environmentPermissionStage);
        }

        final EnvironmentPermissions environmentPermissionProduction = planSpec.environmentPermissionProduction();
        bambooServer.publish(environmentPermissionProduction);
    }
}
