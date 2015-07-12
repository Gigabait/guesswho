function GM:PlayerDeathThink( ply )

	local spectargets = team.GetPlayers( ply:Team() )

	if GAMEMODE:InRound() then
		if not ply.SpecID then 
			ply:Spectate(OBS_MODE_CHASE)
			if spectargets != nil then
				for k,v in pairs(spectargets) do
			    	if v:Alive() then ply.SpecID = k ply:SpectateEntity(v)  break end
				end
			end
			if !ply.SpecID then ply.SpecID = 1 end
		end
		if ply:KeyPressed( IN_ATTACK ) then
			ply.SpecID = ply.SpecID + 1
			if ply.SpecID > #spectargets then
				ply.SpecID = 1
			end
			while !spectargets[ply.SpecID]:Alive() do ply.SpecID = ply.SpecID + 1 if spectargets[ply.SpecID] == nil then break end end -- if player not alive find next alive
			if IsValid(spectargets[ply.SpecID]) then
				ply:SpectateEntity(spectargets[ply.SpecID])
			end
		elseif ply:KeyPressed( IN_ATTACK2 ) then
			ply.SpecID = ply.SpecID - 1 
			if ply.SpecID < 1 then
				ply.SpecID = #spectargets
			end
			while !spectargets[ply.SpecID]:Alive() do ply.SpecID = ply.SpecID - 1 if spectargets[ply.SpecID] == nil then break end end -- if player not alive find next alive
			if IsValid(spectargets[ply.SpecID]) then
				ply:SpectateEntity(spectargets[ply.SpecID])
			end
		end
	end

	if ( ply.NextSpawnTime && ply.NextSpawnTime > CurTime() ) then return end

	--give hiders a 2nd chance if they died in prep
	if ply:Team() == TEAM_HIDING and GAMEMODE:GetRoundState() == PRE_ROUND then
		ply:Spawn()
	end

	if ply:Team() == TEAM_SEEKING or ply:Team() == TEAM_HIDING then return end

	if ( ply:IsBot() || ply:KeyPressed( IN_ATTACK ) || ply:KeyPressed( IN_ATTACK2 ) || ply:KeyPressed( IN_JUMP ) ) then
	
		ply:Spawn()
	
	end
	
end

function GM:PlayerDeath( ply, inflictor, attacker )

	-- Don't spawn for at least 2 seconds
	ply.NextSpawnTime = CurTime() + 2
	ply.DeathTime = CurTime()

	---spectate first alive player in team
	ply:Spectate(OBS_MODE_CHASE)
	local spectargets = team.GetPlayers( ply:Team() )
	if spectargets != nil then
		for k,v in pairs(spectargets) do
	    	if v:Alive() then ply.SpecID = k ply:SpectateEntity(v)  break end
		end
	end
	
	if ( IsValid( attacker ) && attacker:GetClass() == "trigger_hurt" ) then attacker = ply end
	
	if ( IsValid( attacker ) && attacker:IsVehicle() && IsValid( attacker:GetDriver() ) ) then
		attacker = attacker:GetDriver()
	end

	if ( !IsValid( inflictor ) && IsValid( attacker ) ) then
		inflictor = attacker
	end

	-- Convert the inflictor to the weapon that they're holding if we can.
	-- This can be right or wrong with NPCs since combine can be holding a
	-- pistol but kill you by hitting you with their arm.
	if ( IsValid( inflictor ) && inflictor == attacker && ( inflictor:IsPlayer() || inflictor:IsNPC() ) ) then
	
		inflictor = inflictor:GetActiveWeapon()
		if ( !IsValid( inflictor ) ) then inflictor = attacker end

	end

	if ( attacker == ply ) then
	
		net.Start( "PlayerKilledSelf" )
			net.WriteEntity( ply )
		net.Broadcast()
		
		MsgAll( attacker:Nick() .. " suicided!\n" )
		
	return end

	if ( attacker:IsPlayer() ) then
	
		net.Start( "PlayerKilledByPlayer" )
		
			net.WriteEntity( ply )
			net.WriteString( inflictor:GetClass() )
			net.WriteEntity( attacker )
		
		net.Broadcast()
		
		MsgAll( attacker:Nick() .. " killed " .. ply:Nick() .. " using " .. inflictor:GetClass() .. "\n" )
		
	return end
	
	net.Start( "PlayerKilled" )
	
		net.WriteEntity( ply )
		net.WriteString( inflictor:GetClass() )
		net.WriteString( attacker:GetClass() )

	net.Broadcast()
	
	MsgAll( ply:Nick() .. " was killed by " .. attacker:GetClass() .. "\n" )
	
end

function GM:PlayerSpawn( pl )

	--
	-- If the player doesn't have a team in a TeamBased game
	-- then spawn him as a spectator
	--
	if ( GAMEMODE.TeamBased && ( pl:Team() == TEAM_SPECTATOR || pl:Team() == TEAM_UNASSIGNED ) ) then

		GAMEMODE:PlayerSpawnAsSpectator( pl )
		return
	
	end

	if pl:Team() == TEAM_SEEKING then
		player_manager.SetPlayerClass( pl, "player_seeker")
	elseif pl:Team() == TEAM_HIDING then
		player_manager.SetPlayerClass( pl, "player_hiding")
	end

	-- Stop observer mode
	pl:UnSpectate()

	pl:SetupHands()

	player_manager.OnPlayerSpawn( pl )
	player_manager.RunClass( pl, "Spawn" )

	-- Call item loadout function
	hook.Call( "PlayerLoadout", GAMEMODE, pl )
	
	-- Set player model
	hook.Call( "PlayerSetModel", GAMEMODE, pl )

end

function GM:OnPlayerChangedTeam( ply, oldteam, newteam )

	-- Here's an immediate respawn thing by default. If you want to
	-- re-create something more like CS or some shit you could probably
	-- change to a spectator or something while dead.
	if ( newteam == TEAM_SPECTATOR ) then
	
		-- If we changed to spectator mode, respawn where we are
		local Pos = ply:EyePos()
		ply:Spawn()
		ply:SetPos( Pos )
		
	elseif ( oldteam == TEAM_SPECTATOR ) then
	
		-- If we're changing from spectator, join the game
		--disabled ply:Spawn()
	
	else
	
		-- If we're straight up changing teams just hang
		-- around until we're ready to respawn onto the
		-- team that we chose
		
	end
	
	PrintMessage( HUD_PRINTTALK, Format( "%s joined '%s'", ply:Nick(), team.GetName( newteam ) ) )
	
end

function GM:IsSpawnpointSuitable( pl, spawnpointent, bMakeSuitable )

	local Pos = spawnpointent:GetPos()
	
	-- Note that we're searching the default hull size here for a player in the way of our spawning.
	-- This seems pretty rough, seeing as our player's hull could be different.. but it should do the job
	-- (HL2DM kills everything within a 128 unit radius)
	local Ents = ents.FindInBox( Pos + Vector( -16, -16, 0 ), Pos + Vector( 16, 16, 64 ) )
	
	if ( pl:Team() == TEAM_SPECTATOR ) then return true end
	
	local Blockers = 0
	
	for k, v in pairs( Ents ) do
		if ( IsValid( v ) && v != pl && v:GetClass() == "player" && v:Alive() ) then
		
			Blockers = Blockers + 1
			
			if ( bMakeSuitable ) then
				--v:Kill()
			end
			
		end
	end
	
	if ( bMakeSuitable ) then return true end
	if ( Blockers > 0 ) then return false end
	return true

end